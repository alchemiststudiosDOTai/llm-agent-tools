# exa-search.sh

Web search for LLM agents via the Exa API.

## Quick Start

```bash
export EXA_API_KEY=your-key
./exa-search.sh "query"
```

## Options

```
-n, --num <N>         Number of results (default: 10, max: 100)
-t, --type <TYPE>     Search type: auto, neural, fast, deep
-c, --category <CAT>  Category: news, research, github, pdf, company, tweet
-d, --domain <DOM>    Include only this domain
-x, --exclude <DOM>   Exclude this domain
--text                Include full page text
--highlights          Include relevant snippets
--summary             Include AI-generated summary
--after <DATE>        Published after date (YYYY-MM-DD)
--before <DATE>       Published before date (YYYY-MM-DD)
-o, --output <FMT>    Output format: markdown, json (default: markdown)
-h, --help            Show help
```

## Examples

```bash
# Basic search
./exa-search.sh "rust async programming"

# Limit results, get highlights
./exa-search.sh -n 5 --highlights "error handling patterns"

# Search specific domain
./exa-search.sh -d docs.rs "tokio runtime"

# Recent news only
./exa-search.sh -c news --after 2024-01-01 "AI agents"

# JSON output for parsing
./exa-search.sh -o json "claude anthropic" | jq '.results[].url'
```

## Output

### Markdown (default)

```
# Search: "rust async"

1. [Async in Rust](https://example.com)
   Published: 2024-03-15

2. [Tokio Tutorial](https://tokio.rs/tutorial)
   Published: 2024-02-01

---
Results: 10 | Cost: $0.005
```

### JSON

Raw Exa API response. Useful for programmatic parsing.

## Costs

- Basic search: $0.005 per request
- With content (text/highlights/summary): +$0.001 per page

## Dependencies

- `curl`
- `jq`
