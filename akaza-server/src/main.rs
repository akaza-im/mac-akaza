mod handler;
mod jsonrpc;

use std::io::{self, BufRead, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use libakaza::config::{DictConfig, DictEncoding, DictUsage, EngineConfig};
use libakaza::engine::bigram_word_viterbi_engine::BigramWordViterbiEngineBuilder;
use libakaza::graph::reranking::ReRankingWeights;
use libakaza::lm::system_bigram::MarisaSystemBigramLM;
use libakaza::lm::system_unigram_lm::MarisaSystemUnigramLM;
use libakaza::user_side_data::encryption_key::load_or_create_default_encryption_key;
use libakaza::user_side_data::user_data::UserData;
use log::info;

fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .target(env_logger::Target::Stderr)
        .init();

    let model_dir = match std::env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("Usage: akaza-server <model-directory>");
            std::process::exit(1);
        }
    };

    info!("Starting akaza-server with model: {}", model_dir);

    let user_data = Arc::new(Mutex::new(match load_or_create_default_encryption_key() {
        Ok(key) => UserData::load_from_default_path(Some(&key)).unwrap_or_else(|e| {
            log::warn!("Failed to load user data: {e}. Starting with empty user data.");
            UserData::default()
        }),
        Err(e) => {
            log::warn!(
                "Failed to load/create encryption key: {e}. User data will not be persisted."
            );
            UserData::default()
        }
    }));

    let mut dicts: Vec<DictConfig> = Vec::new();
    if let Ok(basedir) = xdg::BaseDirectories::with_prefix("akaza") {
        if let Some(path) = basedir.find_data_file("SKK-JISYO.L") {
            info!("Found SKK-JISYO.L: {}", path.display());
            dicts.push(DictConfig {
                path: path.to_string_lossy().to_string(),
                encoding: DictEncoding::EucJp,
                dict_type: libakaza::config::DictType::SKK,
                usage: DictUsage::Normal,
            });
        }
    }

    for dict_arg in std::env::args().skip(2) {
        let parts: Vec<&str> = dict_arg.rsplitn(2, ':').collect();
        if parts.len() == 2 {
            let path = parts[1];
            let encoding = match parts[0] {
                "eucjp" => DictEncoding::EucJp,
                "utf8" => DictEncoding::Utf8,
                other => {
                    log::warn!("Unknown encoding '{}' for dict '{}', skipping", other, path);
                    continue;
                }
            };
            info!("Loading additional dict: {} ({})", path, parts[0]);
            dicts.push(DictConfig {
                path: path.to_string(),
                encoding,
                dict_type: libakaza::config::DictType::SKK,
                usage: DictUsage::Normal,
            });
        } else {
            log::warn!(
                "Invalid dict argument '{}', expected <path>:<encoding>",
                dict_arg
            );
        }
    }

    let config = EngineConfig {
        model: model_dir.clone(),
        dicts,
        dict_cache: true,
        reranking_weights: ReRankingWeights::default(),
    };

    let engine = BigramWordViterbiEngineBuilder::new(config)
        .user_data(user_data)
        .build()?;

    info!("Engine initialized successfully");

    let unigram_lm = MarisaSystemUnigramLM::load(&format!("{}/unigram.model", model_dir))?;
    let bigram_lm = MarisaSystemBigramLM::load(&format!("{}/bigram.model", model_dir))?;

    let basedir = xdg::BaseDirectories::with_prefix("akaza")?;
    let dict_path_buf = basedir.place_data_file(Path::new("SKK-JISYO.user"))?;
    let dict_path = dict_path_buf
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("dict path contains non-UTF-8 characters"))?
        .to_string();

    let mut handler =
        handler::Handler::new(engine, dict_path, model_dir.clone(), unigram_lm, bigram_lm);

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                log::error!("Failed to read stdin: {}", e);
                break;
            }
        };

        if line.is_empty() {
            continue;
        }

        let response = handler.handle_request(&line);
        writeln!(stdout, "{}", response)?;
        stdout.flush()?;
    }

    handler.flush_learn();
    info!("akaza-server shutting down");
    Ok(())
}
