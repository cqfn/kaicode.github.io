# frozen_string_literal: true

# (The MIT License)
#
# Copyright (c) 2021-2025 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

source 'https://rubygems.org'

gem 'jekyll', '4.3.2'
gem 'jekyll-bits', '0.15'
gem 'jekyll-redirect-from', '0.16.0'
gem 'jekyll-feed', '0.17.0'
gem 'jekyll-paginate', '1.1.0'
gem 'jekyll-sitemap', '1.4.0'

gem "tzinfo", "~> 2.0"
gem "tzinfo-data", platforms: [:x64_mingw, :mingw, :mswin]

# It is possible that you'll bump into some problems while setting up Ruby and Bundler,
# for example `TZInfo::DataSourceNotFound` while attempting to connect
# to a server (if you're a Windows user). This happens because TZInfo needs to
# get a sourse of timezone data on your computer, but it fails. On many Unix-based
# systems (e.g. Linux), TZInfo is able to use the system zoneinfo directory
# as a source of data. However, Windows doesn't include such a directory,
# so the 'tzinfo-data' gem needs to be installed instead. The 'tzinfo-data' gem
# contains the same zoneinfo data, packaged as a set of Ruby modules.
# A solution was proposed by [Adly](https://stackoverflow.com/users/1205392/adly),
# and we added it to the Gemfile. Kindly NOT delete those two 'tzinfo' and 'tzinfo-data'
# strings to avoid this issue.
