# Dockerfile development version
FROM ruby:3.1.2 AS IRM-development

# Default directory
ENV INSTALL_PATH /opt/app
RUN mkdir -p $INSTALL_PATH

# Install gems
WORKDIR $INSTALL_PATH
COPY . .

RUN gem install rails bundler
RUN bundle install \
 # Remove unneeded files (cached *.gem, *.o, *.c)
 && rm -rf /usr/local/bundle/cache/*.gem \
 && find /usr/local/bundle/gems/ -name "*.c" -delete \
 && find /usr/local/bundle/gems/ -name "*.o" -delete

# Start server
CMD ["rails", "server", "-b", "0.0.0.0"]
