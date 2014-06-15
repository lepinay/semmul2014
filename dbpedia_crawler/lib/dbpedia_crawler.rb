# encoding: utf-8

# Module DBpediaCrawler includes some classes for crawling RDF data from
# (a) DBpedia.
# 
# - Crawler: central class, run one for each DBpedia, uses the other classes
# - Queue: provides handling of commands for the crawler
# - Source: provides access to the data of DBpedia
# - Writer: provides means of persisting crawled data
#
# TODO: query related entity data and add it to the data store
# TODO: query all relevant IDs (movies + shows)
# TODO: search for updates
# 
# TODO: try with other DBpedias
# TODO: check bunny options
# TODO: interface of bunny queues / commands
# TODO: validate configuration options
# TODO: logging
# TODO: (maybe) handle SignalExceptions for proper termination
# TODO: testing :)
module DBpediaCrawler

  require_relative 'dbpedia_crawler/crawler'
  require_relative 'dbpedia_crawler/queue'
  require_relative 'dbpedia_crawler/source'
  require_relative 'dbpedia_crawler/writer'

end
