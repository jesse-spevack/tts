# Use official Ruby image
FROM ruby:3.4-slim

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install -y build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development' && \
    bundle config set --local jobs 4 && \
    bundle install

# Copy application code
COPY lib/ ./lib/
COPY config/ ./config/
COPY api.rb ./

# Create output directory for temporary MP3 files
RUN mkdir -p output

# Expose port
EXPOSE 8080

# Start application
CMD ["bundle", "exec", "ruby", "api.rb"]
