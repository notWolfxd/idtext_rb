# DText

A Ruby library for parsing [DText](https://danbooru.donmai.us/wiki_pages/help:dtext),
[Danbooru](https://github.com/danbooru/danbooru)'s text formatting language.

# Pre-requisites
```bash
sudo apt-get install build-essential ragel
```

# Notes from installing via Bundler

1. Add to Gemfile
```bash
gem 'idtext_rb', git: "https://github.com/notWolfxd/idtext_rb.git", require: "dtext"
```
2. Install
```bash
bundle install
```

# Development

1. Modify whatever you need in `/ext/dtext/dtext.cpp.rl`
2. Commit changes
3. Gather changes needed for `/ext/dtext/dtext.cpp` => `ragel -C -o ext/dtext/dtext.cpp ext/dtext/dtext.cpp.rl`
4. Commit the outputed file to GitHub (optional, if you care about versioning)
5. `bundle update`
6. Enter into installed gem directory to compile (i.e. `/home/winterxix/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/bundler/gems/idtext_rb-079386c18688/`
7. `bin/rake compile`
8. Start your application

# Usage

```bash
ruby -rdtext -e 'puts DText.parse("hello world")'
# => <p>hello world</p>
```

# Test

```bash
bin/rake test
```
