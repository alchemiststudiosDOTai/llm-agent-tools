use anyhow::{Context, Result};
use clap::Parser;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "rust-rag-search")]
#[command(about = "Fast FTS5 search for knowledge base", long_about = None)]
struct Args {
    /// Path to SQLite database
    #[arg(short, long)]
    db_path: PathBuf,

    /// Search query
    #[arg(short, long)]
    query: String,

    /// Maximum number of results
    #[arg(short, long, default_value_t = 10)]
    limit: usize,

    /// Maximum snippet length
    #[arg(short = 's', long, default_value_t = 500)]
    max_snippet: usize,

    /// Output format (json, jsonl, text)
    #[arg(short, long, default_value = "jsonl")]
    format: OutputFormat,

    /// Search specific category only
    #[arg(short, long)]
    category: Option<String>,
}

#[derive(Debug, Clone, clap::ValueEnum)]
enum OutputFormat {
    Json,
    Jsonl,
    Text,
}

#[derive(Debug, Serialize, Deserialize)]
struct SearchResult {
    path: String,
    category: String,
    title: String,
    snippet: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    rank: Option<f64>,
}

struct Searcher {
    conn: Connection,
}

impl Searcher {
    fn new(db_path: &PathBuf) -> Result<Self> {
        let conn = Connection::open(db_path)
            .with_context(|| format!("Failed to open database: {:?}", db_path))?;
        Ok(Self { conn })
    }

    fn extract_snippet(&self, content: &str, query: &str, max_length: usize) -> String {
        let content_lower = content.to_lowercase();
        let query_lower = query.to_lowercase();

        // Find first occurrence of query
        if let Some(pos) = content_lower.find(&query_lower) {
            let start = pos.saturating_sub(max_length / 3);
            let end = (pos + query.len() + (2 * max_length / 3)).min(content.len());

            let mut snippet = content[start..end].trim().to_string();

            // Add ellipsis if truncated
            if start > 0 {
                snippet = format!("...{}", snippet);
            }
            if end < content.len() {
                snippet.push_str("...");
            }

            snippet
        } else {
            // If exact match not found, return beginning
            let end = max_length.min(content.len());
            let mut snippet = content[..end].trim().to_string();
            if content.len() > max_length {
                snippet.push_str("...");
            }
            snippet
        }
    }

    fn search(&self, query: &str, limit: usize, max_snippet: usize) -> Result<Vec<SearchResult>> {
        let sql = r#"
            SELECT 
                d.path,
                d.category,
                d.title,
                d.content,
                bm25(docs_fts) as rank
            FROM docs d
            JOIN docs_fts ON d.id = docs_fts.rowid
            WHERE docs_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        "#;

        let mut stmt = self.conn.prepare(sql)?;
        let results = stmt
            .query_map([query, &limit.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,  // path
                    row.get::<_, String>(1)?,  // category
                    row.get::<_, String>(2)?,  // title
                    row.get::<_, String>(3)?,  // content
                    row.get::<_, f64>(4)?,     // rank
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(results
            .into_iter()
            .map(|(path, category, title, content, rank)| {
                let snippet = self.extract_snippet(&content, query, max_snippet);
                SearchResult {
                    path,
                    category,
                    title,
                    snippet,
                    rank: Some(rank),
                }
            })
            .collect())
    }

    fn search_category(
        &self,
        query: &str,
        category: &str,
        limit: usize,
        max_snippet: usize,
    ) -> Result<Vec<SearchResult>> {
        let sql = r#"
            SELECT 
                d.path,
                d.category,
                d.title,
                d.content,
                bm25(docs_fts) as rank
            FROM docs d
            JOIN docs_fts ON d.id = docs_fts.rowid
            WHERE docs_fts MATCH ? AND d.category = ?
            ORDER BY rank
            LIMIT ?
        "#;

        let mut stmt = self.conn.prepare(sql)?;
        let results = stmt
            .query_map([query, category, &limit.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,  // path
                    row.get::<_, String>(1)?,  // category
                    row.get::<_, String>(2)?,  // title
                    row.get::<_, String>(3)?,  // content
                    row.get::<_, f64>(4)?,     // rank
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(results
            .into_iter()
            .map(|(path, category, title, content, rank)| {
                let snippet = self.extract_snippet(&content, query, max_snippet);
                SearchResult {
                    path,
                    category,
                    title,
                    snippet,
                    rank: Some(rank),
                }
            })
            .collect())
    }
}

fn format_results(results: &[SearchResult], query: &str, format: &OutputFormat) -> Result<String> {
    if results.is_empty() {
        return match format {
            OutputFormat::Json | OutputFormat::Jsonl => Ok(String::from("{\"results\":[],\"count\":0}")),
            OutputFormat::Text => Ok(String::from("No results found.")),
        };
    }

    match format {
        OutputFormat::Jsonl => {
            // Compact JSONL format for agent consumption
            let lines: Vec<String> = results
                .iter()
                .map(|r| {
                    serde_json::json!({
                        "p": r.path,
                        "c": r.category,
                        "t": r.title,
                        "s": r.snippet,
                        "r": r.rank
                    })
                    .to_string()
                })
                .collect();
            Ok(lines.join("\n"))
        }
        OutputFormat::Json => {
            let output = serde_json::json!({
                "query": query,
                "count": results.len(),
                "results": results
            });
            Ok(serde_json::to_string_pretty(&output)?)
        }
        OutputFormat::Text => {
            let mut output = Vec::new();
            output.push(format!("Found {} results for '{}':\n", results.len(), query));
            
            for (i, r) in results.iter().enumerate() {
                output.push(format!("{}. [{}] {}", i + 1, r.category, r.title));
                output.push(format!("   Path: {}", r.path));
                output.push(format!("   {}\n", r.snippet));
            }
            
            Ok(output.join("\n"))
        }
    }
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Check if database exists
    if !args.db_path.exists() {
        anyhow::bail!("Database not found: {:?}", args.db_path);
    }

    let searcher = Searcher::new(&args.db_path)?;

    let results = if let Some(category) = &args.category {
        searcher.search_category(&args.query, category, args.limit, args.max_snippet)?
    } else {
        searcher.search(&args.query, args.limit, args.max_snippet)?
    };

    let output = format_results(&results, &args.query, &args.format)?;
    println!("{}", output);

    Ok(())
}
