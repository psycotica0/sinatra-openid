require 'sinatra/base'
require 'openid'
require 'openid/store/filesystem'

class Public < Sinatra::Base
	include OpenID::Server

	enable :sessions

	def logged_in?
		session[:user] && session[:user] == 'meow'
	end

	def server
		if @server.nil?
			dir = Pathname.new(File.dirname($0)).join('db').join('openid-store')
			store = OpenID::Store::Filesystem.new(dir)
			@server = Server.new(store, 'http://localhost:4567/')
		end
		@server
	end

	def respond(oidresp)
		if oidresp.needs_signing
			signed_response = server.signatory.sign(oidresp)
		end
		web_response = server.encode_response(oidresp)

		case web_response.code
		when HTTP_OK
			web_response.body
		when HTTP_REDIRECT
			puts web_response.headers['location']
			[302, {'Location' => web_response.headers['location']}, web_response.body]
		else
			[400, web_response.body]
		end
	end

	def handle(oidreq)
		oidresp = nil
		if oidreq.kind_of?(CheckIDRequest)
			if (oidreq.id_select)
				oidresp = oidreq.answer(false)
			elsif logged_in?
				oidresp = oidreq.answer(true)
			else
				session[:last_req] = oidreq
				return [302, {'Location' => "/login"}, "Login"]
			end
		else
			oidresp = server.handle_request(oidreq)
		end

		respond(oidresp)
	end

	get '/' do
		begin
			oidreq = server.decode_request(params)
		rescue ProtocolError => e
			return [500, e.to_s]
		end
		if oidreq
			handle(oidreq)
		else
			"This is a server"
		end
	end

	post '/' do
		begin
			oidreq = server.decode_request(params)
		rescue ProtocolError => e
			return [500, e.to_s]
		end
		handle(oidreq)
	end

	def logged_in
		'<html><head><title>Login</title></head><body>Neat.<form method="post" action="/logout"><input type="submit" value="Logout" /></form></body></html>'
	end

	get '/login' do
		if logged_in?
			logged_in
		else
			'<html><head><title>Login</title></head><body>Sup Bra?<form method="post"><input type="submit" value="Login" /></form></body></html>'
		end
	end

	post '/logout' do
		session[:user] = nil
		[302, {'Location' => '/login'}, "Logging Out"]
	end

	post '/login' do
		session[:user] = 'meow'
		if session[:last_req].nil?
			logged_in
		else
			oidreq = session[:last_req]
			session[:last_req] = nil
			handle(oidreq)
		end
	end

	get '/user/' do
		'<html><head><link rel="openid2.provider" href="http://localhost:4567/" /></head><body>User</body></html>'
	end
end
