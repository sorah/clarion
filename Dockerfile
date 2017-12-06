FROM sorah/ruby:2.4

EXPOSE 8080

RUN mkdir -p /app /app/tmp /app/lib/clarion

COPY Gemfile* /app/
COPY *.gemspec /app/
COPY lib/clarion/version.rb /app/lib/clarion/version.rb
RUN cd /app && bundle install -j4 --deployment --without 'development test'

WORKDIR /app
CMD ["bundle", "exec", "puma", "-w", "2", "-t", "4:16", "-p", "8080"]
