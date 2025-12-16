# scratchpad.sh

External memory for LLM agent reasoning. Records intermediate states between reasoning steps.

Based on ["Thinking Isn't an Illusion"](https://arxiv.org/abs/2507.17699) which shows scratchpads significantly improve reasoning model performance by providing external memory for tracking state.

## Quick Start

```bash
# Initialize state
./scratchpad.sh set '{"peg_A": [3,2,1], "peg_B": [], "peg_C": []}'

# Check state
./scratchpad.sh get
```

## Commands

```
get [key]           Get current state (or specific key)
set <json>          Set entire state
update <key> <val>  Update a specific key
push <key> <val>    Push value to array at key
pop <key>           Pop value from array at key
log <message>       Append to reasoning log
showlog             Show reasoning log
history             Show state change history
clear               Clear scratchpad
```

## Options

```
-f, --file <PATH>   Scratchpad file (default: /tmp/scratchpad.json)
-h, --help          Show help
```

## Examples

### Tower of Hanoi

```bash
# Initialize puzzle
./scratchpad.sh set '{"peg_A": [3,2,1], "peg_B": [], "peg_C": [], "moves": 0}'

# Log reasoning
./scratchpad.sh log "Move 1: Move disk 1 from A to C"

# Execute move
./scratchpad.sh pop peg_A      # Returns: 1
./scratchpad.sh push peg_C 1
./scratchpad.sh update moves 1

# Check state
./scratchpad.sh get
# {"peg_A": [3,2], "peg_B": [], "peg_C": [1], "moves": 1}

# View reasoning history
./scratchpad.sh showlog
```

### Blocks World

```bash
# Initialize state
./scratchpad.sh set '{
  "on_table": ["A", "B"],
  "stacks": {"C": ["A"]},
  "holding": null,
  "goal": {"B": ["A", "C"]}
}'

# Track reasoning
./scratchpad.sh log "Pick up C from A"
./scratchpad.sh update holding '"C"'
./scratchpad.sh update stacks '{"A": []}'
```

### River Crossing

```bash
./scratchpad.sh set '{
  "left_bank": ["farmer", "wolf", "goat", "cabbage"],
  "right_bank": [],
  "boat_position": "left"
}'
```

## Output

### State (JSON)

```json
{
  "peg_A": [3, 2],
  "peg_B": [],
  "peg_C": [1],
  "moves": 1
}
```

### Reasoning Log

```
[2025-01-15T10:30:00] Move 1: Move disk 1 from A to C
[2025-01-15T10:30:05] Move 2: Move disk 2 from A to B
```

## Dependencies

- `jq`
