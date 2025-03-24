FROM ruby:3.4-alpine
RUN apk add --no-cache build-base git
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
RUN mkdir -p -m 700 wallet
ENTRYPOINT ["ruby", "cli.rb"]
