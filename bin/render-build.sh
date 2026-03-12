#!/usr/bin/env bash
set -o errexit

bundle install

bundle exec rails assets:precompile RAILS_ENV=production SECRET_KEY_BASE=dummy

bundle exec rails assets:clean