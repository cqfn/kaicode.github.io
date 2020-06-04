<img src="https://www.kaicode.org/logo.svg" width="92px"/>

Annual Competition for Young Open Source Projects

You are welcome to submit corrections to this web site. In order to do that,
you will need [Ruby](https://www.ruby-lang.org/en/) 2.3+ and
[Bundler](https://bundler.io/) installed. Then, run this:

```bash
$ bundle update
$ bundle exec jekyll serve
```

In a few seconds you should be able to see the site
at `http://localhost:4000`. Make your changes and refresh the page in the browser.
If everything is fine, submit a pull request.


It is possible that you'll bump into some problems while setting this all up,
for example `TZInfo::DataSourceNotFound` while attempting to connect
to a server (if you're a Windows user). This happens because TZInfo needs to
get a sourse of timezone data on your computer, but it fails. On many Unix-based 
systems (e.g. Linux), TZInfo is able to use the system zoneinfo directory 
as a source of data. However, Windows doesn't include such a directory, 
so the tzinfo-data gem needs to be installed instead. The tzinfo-data gem 
contains the same zoneinfo data, packaged as a set of Ruby modules.


The following steps to resolve this problem are:

1. Put this into your terminal:

```bash
gem install tzinfo-data
```

2. Change the gemfile by adding the line via Notepad:

```bash
gem "tzinfo-data", platforms: [:x64_mingw, :mingw, :mswin]
```

3. Update bundle in the terminal:

```bash
bundle update
```

The problem is solved directly this way.

Proposed by [Adly](https://stackoverflow.com/users/1205392/adly)
