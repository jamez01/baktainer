FROM ruby:3.3-alpine

RUN mkdir /backups

# Install dependencies
RUN apk add --no-cache \
  build-base \
  libffi-dev \
  linux-headers \
  postgresql-dev \
  tzdata \
  git \
  curl

RUN gem install bundler -v 2.6.7

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh


# Set the working directory
WORKDIR /app
# Copy the Gemfile and Gemfile.lock
COPY ./app/Gemfile ./app/Gemfile.lock /app/
# Install the gems
RUN bundle config set --local deployment 'true' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test' && \
    bundle install


COPY ./app/ /app/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bundle", "exec", "ruby", "./app.rb"]
