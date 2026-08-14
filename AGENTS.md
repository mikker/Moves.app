# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Coding Guidelines

- Don't add comments. At all. Unless something is VERY convoluted or looks confusing.

## Building and Running

- The project uses Xcode and Swift Package Manager for dependencies
- Build the project using: `xcodebuild -scheme Moves -configuration Debug build`
- Clean and rebuild with: `xcodebuild -scheme Moves -configuration Debug clean build`
- The build server configuration is in `buildServer.json`

## Architecture Overview

Moves is a macOS menu bar application that helps position windows on the screen through keyboard shortcuts and URL schemes.

### Key Components

1. **Window Management**
   - `WindowPosition` - Enum for different window positions (center, topLeft, etc.)
   - `WindowAction` - Special window operations like maximizing height/width
   - `WindowSize` - Size specifications (relative or absolute)
   - `WindowOperation` - Either a position+size or an action
   - `TemplateType` - Predefined window layouts/templates

2. **Accessibility Integration**
   - Uses AXSwift for macOS Accessibility API integration
   - `ActiveWindow` - Core functionality for manipulating window positions

3. **URL Scheme Support**
   - URL format: `moves://template/{template-name}`
   - URL format: `moves://custom/{position}?parameters`
   - Handled in AppDelegate's `application(_:open:)` method

4. **Defaults & Settings**
   - Uses `Defaults` package for preference management
   - Settings UI with General and Excludes sections

5. **Auto-updates**
   - Uses Sparkle framework for application updates