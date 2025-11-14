"""Tests for main module."""

from main import greet, handler


def test_greet() -> None:
    """Test greet function."""
    result = greet("Test")
    assert result == "Hello, Test!"


def test_greet_with_different_name() -> None:
    """Test greet with different input."""
    result = greet("Alice")
    assert result == "Hello, Alice!"


def test_handler_with_name() -> None:
    """Test Lambda handler with name in event."""
    event = {"name": "Lambda"}
    result = handler(event, None)

    assert result["statusCode"] == 200
    assert "message" in result["body"]
    assert result["body"]["message"] == "Hello, Lambda!"


def test_handler_without_name() -> None:
    """Test Lambda handler without name (default)."""
    event: dict[str, str] = {}
    result = handler(event, None)

    assert result["statusCode"] == 200
    assert result["body"]["message"] == "Hello, World!"


def test_handler_response_structure() -> None:
    """Test Lambda handler response structure."""
    event = {"name": "Test"}
    result = handler(event, None)

    assert "statusCode" in result
    assert "headers" in result
    assert "body" in result
    assert "Content-Type" in result["headers"]
