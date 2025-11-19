"""Main application module with example Lambda handler."""

from typing import Any


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    AWS Lambda handler function.

    Args:
        event: Lambda event data
        context: Lambda context object

    Returns:
        Response dictionary with statusCode and body
    """
    name = event.get("name", "World")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": {"message": f"Hello, {name}!", "version": "0.1.0"},
    }


def greet(name: str) -> str:
    """
    Generate a greeting message.

    Args:
        name: The name to greet

    Returns:
        Greeting message string
    """
    return f"Hello, {name}!"


if __name__ == "__main__":
    # Example usage
    result = greet("Python 3.13")
    print(result)
