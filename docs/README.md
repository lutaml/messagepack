# MessagePack Documentation

This directory contains the documentation site for the MessagePack Ruby gem, built with Jekyll and the just-the-docs theme.

## Building locally

### Prerequisites

- Ruby 3.3 or higher
- Bundler

### Install dependencies

```bash
cd docs
bundle install
```

### Build the site

```bash
bundle exec jekyll build
```

The built site will be in `_site/`.

### Serve locally

```bash
bundle exec jekyll serve
```

Visit `http://localhost:4000/messagepack/` to view the site.

## Running link checker

Install lychee:

```bash
# macOS
brew install lychee

# Or with cargo
cargo install lychee

# Or use Docker
docker run -v $(pwd):/work lycheeverse/lychee ./docs
```

Run link checker:

```bash
# Build the site first
bundle exec jekyll build

# Check links
lychee --config lychee.toml _site/**/*.html
```

## Documentation structure

- `index.adoc` - Main entry point
- `_pages/` - Core topics (fundamental concepts)
- `_tutorials/` - Step-by-step learning guides
- `_guides/` - Task-oriented documentation
- `_references/` - Technical specifications and API docs

## Adding new documentation

1. Create new `.adoc` file in the appropriate collection directory
2. Add YAML front matter with `title`, `parent`, and `nav_order`
3. Follow the template structure:
   - Purpose section
   - References section
   - Concepts section
   - Examples section
4. Update the collection's index.adoc to include the new page

## CI/CD

Documentation is automatically built and deployed to GitHub Pages:
- On push to `main` branch
- When files in `docs/` change

Links are automatically checked with lychee on every push and PR.
