# Error Handling Pattern

## Context
Consistent error handling across the application ensures better debugging and user experience.

## Pattern

### Python Error Handling
```python
class AppError(Exception):
    """Base application error"""
    def __init__(self, message, code=None, details=None):
        self.message = message
        self.code = code
        self.details = details or {}
        super().__init__(self.message)

def safe_operation(func):
    """Decorator for safe execution"""
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except AppError:
            raise  # Re-raise app errors
        except Exception as e:
            logger.error(f"Unexpected error in {func.__name__}: {e}")
            raise AppError(f"Operation failed: {func.__name__}", 
                         code="INTERNAL_ERROR",
                         details={"original": str(e)})
    return wrapper
```

### Bash Error Handling
```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Error handler function
error_handler() {
    local line_no=$1
    echo "Error on line $line_no"
    exit 1
}

trap 'error_handler $LINENO' ERR
```

## Usage
- Always use specific error types
- Include context in error messages
- Log errors appropriately
- Provide user-friendly messages

## Related
- See debug_history/common_errors.md for debugging tips
- See qa/error_recovery.md for recovery strategies