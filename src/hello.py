def hello(name: str = "World") -> str:
    """Return a greeting for name.

    Examples:
        >>> hello()
        'Hello, World!'
        >>> hello('Alice')
        'Hello, Alice!'
    """
    return f"Hello, {name}!"
