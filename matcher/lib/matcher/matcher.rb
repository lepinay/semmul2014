require 'matrix'
require 'date'
require 'levenshtein'
require 'set'




class Matcher::Matcher

    def initialize
        @virtuoso = Matcher::Virtuoso.new
        @default_threshold = 0.8
        @debug = false
    end

    # find:
    def find(entity_uri)
        entity_tripels = @virtuoso.get_triples(entity_uri)
        identic = find_same(entity_tripels)

        # trying to be more rubyiomatic
        unless identic.empty?
            return identic
        else
            matching = find_thresh_matching(entity_tripels, @default_threshold)
            # matching will be a list of matches (sorted), or nil
            return matching
        end
    end


    def find_same(entity_triples)
        same_entities = []

        same_entities.concat(@virtuoso.get_same_as(entity_triples))

        # check for imdb ids if it is a movie
        entity_type = entity_triples.get_type()
        movie_type = "http://semmul2014.hpi.de/lodofmovies.owl#Movie"
        if entity_type == movie_type
            imdb_id = entity_triples.get_imdb_id()
            @virtuoso.get_movie_subjects_by_imdb(imdb_id).each do |same_ent|
                if !same_ent == entity_triples.subject
                    same_entities << same_ent
                end
            end
        end

        # todo: use freebase_mid from dbpedia

        if same_entities.empty?
            return Set.new()
        else
            return Set.new(same_entities)
        end
    end

    def find_thresh_matching(entity_triples, threshold)
        matching = find_matching(entity_triples)
        if matching.size > 0
            if matching[-1][1] >= threshold
                matching_uri = RDF::URI.new(matching[-1][0])
                return matching_uri
            end
        end
        return nil
    end

    def find_best_matching(entity_triples)
        matching = find_matching(entity_triples)
        if matching.size > 0
            matching_uri = RDF::URI.new(matching[-1][0])
            return matching_uri
        end
        return nil
    end

    def find_matching(entity_triples)
        entity_type = entity_triples.get_type()

        # get all with same type from virtuoso
        all_subjects = @virtuoso.get_entities_of_type(entity_type)
        if @debug
            all_subjects = all_subjects[1..5]
        end

        all_matches = {}

        #puts "Calculating matches ..."
        all_subjects_size = all_subjects.size
        counter = 0
        all_subjects.each do |subject_uri|
            if entity_triples.subject != subject_uri
                # calculate match
                other_triples = @virtuoso.get_triples(subject_uri)
                match = calculate_match(entity_triples, other_triples, entity_type)
                counter += 1
                #STDOUT.write("\r #{counter}/#{all_subjects_size}")
                #STDOUT.flush
                all_matches[subject_uri.to_s] = match
            end
        end
        #puts ""

        #puts "matched against #{all_matches.size} subjects"
        all_sorted_matches = all_matches.sort_by {|uri, match| match}

        return all_sorted_matches
    end

	# match: 
	# => movies
	# => persons
	# => locations

    def calculate_match(a_triples, b_triples, type)

        # todo: put into config
        movie = "http://schema.org/Movie"
        person = "http://schema.org/Person"
        organization = "http://schema.org/Organization"
        director = "http://semmul2014.hpi.de/lodofmovies.owl#Director"
        performance = "http://semmul2014.hpi.de/lodofmovies.owl#Performance"

        case type
            when movie
                return match_movie(a_triples, b_triples)
            when person
                return person_match(a_triples, b_triples)
            when director
                return person_match(a_triples, b_triples)
            when organization
                return 0.0 # todo: match org.
            when performance
                return performance_match(a_triples, b_triples)
            else
                return 0.0
        end
    end

    def type_match(a,b)
        type_uri = RDF::URI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
        types_a = a.get_o(type_uri)
        types_b = b.get_o(type_uri)

        # check if one of the types matches
        types_a.each do |type_a|
            types_b.each do |type_b|
                if types_a == types_b
                    return true
                end
            end
        end

        return false
    end


    def performance_match(a,b)

        # match character
        character_a = @virtuoso.get_triples(a.get_character()).get_name().to_s
        character_b = @virtuoso.get_triples(b.get_character()).get_name().to_s
        match_char = levenshtein_match(character_a, character_b)

        # match actor
        actor_a_uri = a.get_actor()[0]
        actor_b_uri = b.get_actor()[0]
        actor_a = @virtuoso.get_triples(actor_a_uri)
        actor_b = @virtuoso.get_triples(actor_b_uri)
        match_actor = person_match(actor_a, actor_b)

        w_character = 0.4
        w_actor = 0.6

        match_degree = (w_character * match_char) + (w_actor * match_actor)
        return match_degree
    end

	def match_movie(a,b)
		# title, release_date, person, distributor, actors

        title_a = a.get_name.to_s
        title_b = b.get_name.to_s
        title_match = levenshtein_match(title_a, title_b)

        # todo: fast-forward ?

        a_date = a.get_release_date
        b_date = b.get_release_date
        use_release_date = true # tmdb has no release date
        release_date_match = 0
        if a_date.nil? or b_date.nil?
            use_release_date = false
        else
            release_date_match = date_match(a_date, b_date)
        end

        actors_match = movie_actors_match(a,b)

        w_title = 0.5
        w_release = 0.2
        w_actors = 0.3
        if !use_release_date
            w_title = w_title + (w_release * 0.5)
            w_actors = w_actors + (w_release * 0.5)
            w_release = 0
        end

        match_degree = (w_title * title_match) + (w_release * release_date_match) + (w_actors * actors_match)

		return match_degree
	end

    def person_match(a,b)

        # --> match names
        names_a = []
        a.get_alternative_names.each do |alt_name_a|
            names_a << alt_name_a.to_s
        end
        names_a << a.get_name.to_s

        names_b = []
        b.get_alternative_names.each do |alt_name_b|
            names_b << alt_name_b.to_s
        end
        names_b << b.get_name.to_s

        # todo: first_name, last_name, name will be given with different info
        name_alias_match = max_name_or_alias_match(names_a, names_b)

        # --> birthdate match
        birth_date_a = a.get_birthdate()
        birth_date_b = b.get_birthdate()
        birthdate_match = 0
        if !birth_date_a.nil? and !birth_date_b.nil?
            use_birthdate = true
            birthdate_match = date_match(a.get_birthdate, b.get_birthdate)
        else
            # if there is no birthdate, then we cannot use 0, as this would distort the result
            # in this case, we have to rely on the known information
            use_birthdate = false
        end

        # todo: birthplace match as string-match

        #birthplace_match = location_match(a[:birthplace],b[:birthplace])
        # todo: vector over works

        w_name_alias = 0.5
        w_birthdate = 1-w_name_alias
        #w_birthplace = 0.2
        if !use_birthdate
            w_name_alias += w_birthdate
        end

        person_match = (w_name_alias*name_alias_match) + (w_birthdate*birthdate_match) # + (w_birthplace*birthplace_match)
    end

    def location_match(a,b)
        # location distance
        a_pos = {:lat  => a[:latitude], :long => a[:longitude]}
        b_pos = {:lat => b[:latitude], :long => b[:longitude]}
        distance_match = lat_long_match(a_pos, b_pos)

        # location name
        names_a = a[:aliases]
        names_a << a[:name]
        names_b = b[:aliases]
        names_b << b[:name]
        name_match = max_name_or_alias_match(names_a, names_b)

        # todo: country
        # todo: is contained by

        w_distance = 0.7
        w_name = 1-w_distance

        location_match = (w_distance * distance_match) + (w_name * name_match)
        return location_match
    end

    #private

	def levenshtein_match(a,b)
		a = a.downcase
		b = b.downcase
		normalizer = (a.size >= b.size ? a.size : b.size)
		match_degree =  1 - (levenshtein_distance(a,b) / normalizer.to_f)
		return match_degree
	end

	def levenshtein_distance(s, t)
	  m = s.length
	  n = t.length
	  return m if n == 0
	  return n if m == 0
	  d = Array.new(m+1) {Array.new(n+1)}

	  (0..m).each {|i| d[i][0] = i}
	  (0..n).each {|j| d[0][j] = j}
	  (1..n).each do |j|
	    (1..m).each do |i|
	      d[i][j] = if s[i-1] == t[j-1]  # adjust index into string
	                  d[i-1][j-1]       # no operation required
	                else
	                  [ d[i-1][j]+1,    # deletion
	                    d[i][j-1]+1,    # insertion
	                    d[i-1][j-1]+1,  # substitution
	                  ].min
	                end
	    end
	  end
	  d[m][n]
	end

	def release_date_match(a,b)

	end

	def date_match(a,b)
		# make dates numerical
		if a >= b
			lower_date = b
			upper_date = a
		else
			lower_date = a
			upper_date = b
		end
		
		lower_date = DateTime.parse(lower_date.to_s)
		upper_date = DateTime.parse(upper_date.to_s)

		# calculate match
		std_dev = 3 * 30 # 6 months
		mean = 0
		lower_date_i = 0
		difference_i = (upper_date - lower_date).to_i
		match_degree = normal_slope(difference_i, mean, std_dev)
		# ignore too small values
		if match_degree < 0.001
			return 0
		end

		return match_degree
	end

	def lat_long_match(a,b)
		d = haversine_distance(a[:lat], a[:long], b[:lat], b[:long])
		return normal_slope(d,0, 10) # sigma = 36 km
	end

	def max_name_or_alias_match(names_a, names_b)
		max_match = 0
        names_a.each do |name_a|
            names_b.each do |name_b|
                match = levenshtein_match(name_a.downcase, name_b.downcase)
                if match > max_match
                    max_match = match
                end
            end
        end
        return max_match
	end

	def name_alias_match(a,b)
		name_a = a[:name].downcase
		name_b = b[:name].downcase
		aliases_a = a[:aliases]
		aliases_b = b[:aliases]

		# name match
		name_match = levenshtein_distance(name_a,name_b)
		
		# find the max matching alias
		max_alias_a = nil
		max_alias_match = 0
		aliases_a.each do |alias_a|
			aliases_b.each do |alias_b|
				alias_match = levenshtein_match(alias_a, alias_b)
				if alias_match > max_alias_match
					max_alias_a = alias_a
					max_alias_match = alias_match
				end
			end
		end

		# calculate match
		name_weight = 0.25
		max_alias_weight = 1 - name_weight
		name_alias_match = (name_weight * name_match) + (max_alias_weight * max_alias_match)
		return name_alias_match
	end

	#def distributor_match(a,b)
	#end

	def movie_actors_match(a,b)
        equivalence_threshold = 0.3 # 0.99 # matches > 99% are identic

        a_actors = @virtuoso.get_actor_triples(a)
        b_actors = @virtuoso.get_actor_triples(b)

        # find match degrees between all actors
        all_matches = {}
        union_size = 0.0

        a_actors.each do |actor_a|
            b_actors.each do |actor_b|
                # todo: actor match that includes works
                if all_matches.has_key?([actor_b, actor_a])
                    all_matches[[actor_a, actor_b]] = all_matches[[actor_b, actor_a]]
                    next
                end

                match = person_match(actor_a, actor_b)
                all_matches[[actor_a, actor_b]] = match
                if match >= equivalence_threshold
                    union_size += 1
                end
            end
        end

        # use dice coefficient to measure similarity between actor sets
        # sim = 2|A union B|/|A|+|B|
        sim = 2 * union_size / (a_actors.size.to_f + b_actors.size.to_f)
        return sim
	end
end

def haversine_distance(lat1,lon1,lat2,lon2)
	earth_radius = 6371 # km
	phi_1 = radians(lat1)
	phi_2 = radians(lat2)
	dphi = radians(lat2-lat1)
	dlambda = radians(lon2-lon1)
	a = Math.sin(dphi/2)**2 + (Math.cos(phi_1) * Math.cos(phi_2) * Math.sin(dlambda/2)**2)
	c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
	d = earth_radius * c
	return d

end

def euclidean_distance(x1,y1,x2,y2)
	return Math.sqrt(((x1-x2)**2)+(y1-y2))
end

def normal_slope(x, mu, sigma)
	pdf = Math.exp((-1.0*(x-mu)**2)/(2*sigma**2))
	return pdf
end

def radians(deg)
	return (deg/180) * Math::PI
end



