# Contributing to Zed Mobile

Thank you for your interest in contributing to Zed Mobile! This document provides guidelines and information for contributors.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Documentation](#documentation)
- [Community Guidelines](#community-guidelines)

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- Flutter SDK (latest stable version)
- Android Studio or VS Code with Flutter plugins
- Git installed and configured
- Basic knowledge of Dart and Flutter development
- Access to a physical Android/iOS device or emulator

### First-time Setup

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/yourusername/zed-mobile.git
   cd zed-mobile
   ```

2. **Set up the upstream remote**
   ```bash
   git remote add upstream https://github.com/zed-industries/zed-mobile.git
   ```

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Verify setup**
   ```bash
   flutter doctor
   flutter test
   ```

## Development Setup

### Environment Configuration

1. **Flutter Version**: Use the version specified in `.fvmrc` if present
2. **IDE Setup**: 
   - VS Code: Install Flutter and Dart extensions
   - Android Studio: Install Flutter plugin
3. **Device Setup**: Enable developer options and USB debugging on Android devices

### Running the App

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Run with hot reload (development)
flutter run --debug

# Run release build
flutter run --release
```

## Code Style

### Dart Code Style

We follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style) with these additions:

1. **Line Length**: Maximum 80 characters
2. **Import Organization**:
   ```dart
   // Dart imports
   import 'dart:async';
   import 'dart:io';
   
   // Flutter imports
   import 'package:flutter/material.dart';
   import 'package:flutter/services.dart';
   
   // Third-party package imports
   import 'package:provider/provider.dart';
   
   // Local imports
   import '../models/message.dart';
   import '../widgets/custom_button.dart';
   ```

3. **File Naming**: Use snake_case for file names
4. **Class Naming**: Use PascalCase for class names
5. **Variable Naming**: Use camelCase for variables and functions

### Widget Structure

```dart
class ExampleWidget extends StatelessWidget {
  // Constants first
  static const String title = 'Example';
  
  // Fields
  final String message;
  final VoidCallback? onTap;
  
  // Constructor
  const ExampleWidget({
    super.key,
    required this.message,
    this.onTap,
  });
  
  // Build method
  @override
  Widget build(BuildContext context) {
    return Container(
      // Widget implementation
    );
  }
  
  // Private methods last
  void _handleTap() {
    onTap?.call();
  }
}
```

### Formatting

Use `dart format` to automatically format code:

```bash
# Format all Dart files
dart format .

# Check formatting without applying changes
dart format --set-exit-if-changed .
```

## Commit Guidelines

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting, etc.)
- **refactor**: Code refactoring
- **perf**: Performance improvements
- **test**: Adding or updating tests
- **chore**: Build process or auxiliary tool changes

### Examples

```bash
feat(ui): add message bubble component

Add reusable message bubble widget with support for:
- User and assistant message types
- Markdown rendering
- Copy to clipboard functionality

Closes #123

fix(websocket): handle connection timeout properly

- Add exponential backoff for reconnection attempts
- Improve error messages for timeout scenarios
- Add unit tests for timeout handling

docs: update installation instructions

chore(deps): update flutter to 3.32.8
```

### Commit Best Practices

- Make atomic commits (one logical change per commit)
- Write clear, descriptive commit messages
- Reference issue numbers when applicable
- Keep the first line under 50 characters
- Use the body to explain what and why, not how

## Pull Request Process

### Before Submitting

1. **Sync with upstream**
   ```bash
   git fetch upstream
   git checkout main
   git merge upstream/main
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Run tests and checks**
   ```bash
   flutter test
   flutter analyze
   dart format --set-exit-if-changed .
   ```

### PR Guidelines

1. **Title**: Use conventional commit format
2. **Description**: Include:
   - What changes were made
   - Why the changes were necessary
   - How to test the changes
   - Screenshots for UI changes
   - Related issue numbers

3. **Size**: Keep PRs focused and reasonably sized
4. **Documentation**: Update relevant documentation
5. **Tests**: Add tests for new functionality

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Manual testing completed
- [ ] All tests pass

## Screenshots (if applicable)
[Add screenshots here]

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

### Review Process

1. **Automated Checks**: Ensure CI passes
2. **Code Review**: Address reviewer feedback
3. **Testing**: Verify functionality works as expected
4. **Approval**: Minimum one approval from maintainer
5. **Merge**: Squash and merge preferred

## Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage

# Run specific test file
flutter test test/widget_test.dart

# Run tests in watch mode
flutter test --reporter expanded --verbose
```

### Test Structure

- **Unit Tests**: `test/unit/`
- **Widget Tests**: `test/widgets/`
- **Integration Tests**: `test/integration/`

### Writing Tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_mobile/models/message.dart';

void main() {
  group('Message', () {
    test('should create message with required fields', () {
      // Arrange
      const content = 'Hello world';
      const type = MessageType.user;
      
      // Act
      final message = Message(
        id: '1',
        threadId: 'thread-1',
        content: content,
        type: type,
        timestamp: DateTime.now(),
      );
      
      // Assert
      expect(message.content, equals(content));
      expect(message.type, equals(type));
    });
  });
}
```

## Documentation

### Code Documentation

- Use `///` for public API documentation
- Document complex business logic
- Add examples for public methods
- Keep documentation up to date

```dart
/// A widget that displays a message bubble.
///
/// Supports both user and assistant message types with different
/// styling and alignment.
///
/// Example:
/// ```dart
/// MessageBubble(
///   message: Message(
///     content: 'Hello!',
///     type: MessageType.user,
///   ),
/// )
/// ```
class MessageBubble extends StatelessWidget {
  /// The message to display.
  final Message message;
  
  /// Creates a message bubble widget.
  const MessageBubble({
    super.key,
    required this.message,
  });
```

### README Updates

- Update features list for new functionality
- Add new dependencies to the installation section
- Update screenshots when UI changes significantly
- Keep architecture diagrams current

## Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Report inappropriate behavior to maintainers

### Communication

- **Issues**: Use GitHub issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and ideas
- **Discord**: Join the Zed Discord for real-time chat

### Getting Help

1. **Documentation**: Check existing docs first
2. **Search**: Look through existing issues and discussions
3. **Ask**: Create a new discussion or issue if needed
4. **Be Specific**: Provide detailed information about your problem

## Issue Guidelines

### Bug Reports

Include:
- Flutter version (`flutter --version`)
- Device/OS information
- Steps to reproduce
- Expected vs actual behavior
- Error messages or logs
- Screenshots if applicable

### Feature Requests

Include:
- Clear description of the feature
- Use case and motivation
- Proposed implementation approach
- Consider alternative solutions

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist

- [ ] Update version in `pubspec.yaml`
- [ ] Update CHANGELOG.md
- [ ] Create release tag
- [ ] Build and test release candidates
- [ ] Update app store listings

## Questions?

If you have questions about contributing, please:

1. Check this document first
2. Search existing issues and discussions
3. Create a new discussion with the "question" label
4. Reach out to maintainers on Discord

Thank you for contributing to Zed Mobile! 🚀