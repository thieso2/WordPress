# Development image for the Rails rebuild. Run via `docker compose up` (see compose.yaml).
FROM ruby:3.3.8-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl libpq-dev libyaml-dev postgresql-client \
      default-libmysqlclient-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Match the lockfile's BUNDLED WITH so the resolution is byte-identical.
RUN gem install bundler -v 4.0.19

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
