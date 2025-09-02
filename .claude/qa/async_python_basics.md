# Async Python Basics Q&A

## Q: What is async/await in Python?

Async/await is a way to write concurrent code using coroutines. It allows you to run multiple operations concurrently without blocking.

## Q: When should I use async?

Use async when:
- Making multiple I/O operations (network requests, file operations)
- Need to handle many concurrent connections
- Want to improve performance without threading complexity

Don't use async when:
- CPU-bound operations (use multiprocessing instead)
- Simple sequential operations
- Libraries don't support async

## Q: Basic async pattern?

```python
import asyncio

async def fetch_data(url):
    # Simulate network request
    await asyncio.sleep(1)
    return f"Data from {url}"

async def main():
    # Run concurrently
    results = await asyncio.gather(
        fetch_data("api1.com"),
        fetch_data("api2.com"),
        fetch_data("api3.com")
    )
    return results

# Run the async function
data = asyncio.run(main())
```

## Q: Common pitfalls?

1. **Forgetting await**: Coroutines must be awaited
```python
# Wrong
result = async_function()  # Returns coroutine object

# Right
result = await async_function()
```

2. **Blocking in async**: Don't use blocking calls
```python
# Wrong
async def bad():
    time.sleep(1)  # Blocks entire event loop

# Right
async def good():
    await asyncio.sleep(1)  # Non-blocking
```

3. **Mixing sync and async**: Be careful with context
```python
# Use asyncio.to_thread for sync functions
async def run_sync():
    result = await asyncio.to_thread(blocking_function, arg1, arg2)
    return result
```

## Q: How to handle errors?

```python
async def safe_fetch(url):
    try:
        return await fetch_data(url)
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return None

# Or use asyncio.gather with return_exceptions
results = await asyncio.gather(
    fetch_data("url1"),
    fetch_data("url2"),
    return_exceptions=True
)
```

## Related
- See patterns/async_patterns.md for advanced patterns
- See debug_history/async_debugging.md for debugging tips