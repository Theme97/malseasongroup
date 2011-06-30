http = require 'http'
fs = require 'fs'
$ = require './php.js'

# check input
if !(topicid = process.argv[2])?
	console.error 'Pass in a topic ID onegaishimasu!'
	process.exit 1

# fetch
console.log "fetching topic #{topicid}..."
http.get {host: 'myanimelist.net', port: 80, path: '/forum/?topicid=' + topicid}, (res) ->
	data = ''
	res
		.on 'error', (e) ->
			console.error 'error: ' + e.message
		.on 'data', (d) ->
			data += d.toString 'utf8'
		.on 'end', ->
			console.log 'received! now parsing...'
			new VoteCounter data, (votes, users) ->
				tally = ({name, count} for name, count of votes)
				tally.sort (a, b) -> b.count - a.count
				str = (i.count + ' - ' + i.name for i in tally).join '\r\n'
				str += '\r\n\r\n'
				
				tally = ({name, count} for name, count of users)
				tally.sort (a, b) -> `(a.name == b.name) ? 0 : ((a.name > b.name) ? 1 : -1)`
				str += (i.name + ': ' + i.count + ' votes' for i in tally).join '\r\n'
				str += '\r\n\r\n'
				
				fs.writeFile 'tally-' + topicid + '.txt', str

class VoteCounter
	constructor: (data, cb) ->
		@cb = cb
		@votes = {}
		@users = {}
		console.log '---'
		
		# title
		@title = @match data, '<title>', ' - Forums - '
		console.log 'Thread Title: ' + @title
		
		# choices
		@choices =
			for i in @match(data, '<div class="spoiler">', '</div>').split('<br />')
				@pretty(i)
		console.log 'Choices: ' + @choices.length
		
		@choices2 = {}
		for choice in @choices
			@votes[choice] = 0
			@choices2[choice] = choice.replace(/\W/g, '').toLowerCase().substr(0, 50)
		
		# pages
		@pages = parseInt @match data, 'Pages (', ')'
		console.log 'Pages: ' + @pages
		
		# fetch!
		console.log ''
		console.log 'Fetching pages...'
		@page = 1
		@parsePage data
	
	# we wait for previous pages to finish because we don't want
	# to slam MAL all at once with a bunch of concurrent requests
	parsePage: (data) ->
		op = -1 if @page is 1
		for post in data.match /<table border="0" cellpadding="0" cellspacing="0" width="100%">[^]*?<\/table>/g
			# skip OP
			continue if op = !~op
			
			# get user
			username = @match post, '<strong>', '</strong>'
			@users[username] ?= 0
			
			# get post
			id = parseInt @match post, 'class="postnum">', '</a>'
			post = post.match(/<div id="message\d+">([^]*?)<div class="postActions">/i)[1]
			post = post.replace /<em>Modified by .*?<\/em>/i, ''
			
			# parse post
			lines = (@pretty i for i in post.split '<br />')
			for line in lines
				# 1: blank line?
				continue if line is ''
				
				# 2: user still has votes?
				break unless @users[username] < 3
				
				# 3: levenshtein dat shit
				best = {choice: '', dist: -1}
				for choice in @choices
					dist = $.levenshtein @standardize(line), @standardize(choice.toLowerCase())
					best = {choice: choice, dist: dist} if dist < best.dist or best.dist == -1
				
				# 3b: try again, but strip off everything after "by"
				if best.dist > 3
					for choice in @choices
						dist = $.levenshtein @standardize(line), @standardize(choice.substr(0, choice.indexOf('" by') + 1))
						best = {choice: choice, dist: dist} if dist < best.dist or best.dist == -1
				
				# 3c: if that don't work, use more gun
				# strip all non-alphanum and check if any of the choices appear exactly in the line
				# (of course, choices are also stripped, but we also trunc to 50 characters)
				if best.dist > 3
					line2 = line.replace(/\W/g, '').toLowerCase()
					(best = {choice: choice, dist: -1} if line2.indexOf(choice2) isnt -1) for choice, choice2 of @choices2
				
				if best.dist <= 3
					@users[username]++
					@votes[best.choice]++
				else
					console.warn '--- MATCH FAIL ---'
					console.warn 'post: #' + id + ' by ' + username
					console.warn 'line: ' + line
					console.warn 'best: ' + best.choice
					console.warn 'dist: ' + best.dist
					console.warn ''
		
		console.log "[page #{@page}]"
		
		if @page++ < @pages
			http.get {host: 'myanimelist.net', port: 80, path: "/forum/?topicid=#{topicid}&show=#{20 * (@page - 1)}"}, (res) =>
				data = ''
				res
					.on 'error', (e) ->
						console.error 'error: ' + e.message
					.on 'data', (d) ->
						data += d.toString 'utf8'
					.on 'end', =>
						@parsePage data
		else
			@cb @votes, @users
	
	match: (str, from, to, start = 0) ->
		a = from.length + str.indexOf from, start
		b = str.indexOf to, a
		str.substring a, b
	
	pretty: (str) ->
		$.html_entity_decode str.replace(/<.+?>/g, '').replace(/^[\s-]+|\s+$/, ''), 'ENT_QUOTES'

	standardize: (str) ->
		str.toLowerCase().replace(/[^\w\s]/g, '').replace(`/ {2,}/g`, ' ')
