require 'sinatra/base'
require 'openid'
require 'openid/store/filesystem'

require File.expand_path '../secrets.rb', __FILE__

class Public < Sinatra::Base
	include OpenID::Server

	enable :sessions

	def logged_in?
		session[:user] && session[:user] == Secrets.user_value
	end

	def server
		if @server.nil?
			dir = Pathname.new(File.dirname($0)).join('db').join('openid-store')
			store = OpenID::Store::Filesystem.new(dir)
			@server = Server.new(store, Secrets.endpoint)
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
			elsif oidreq.immediate
				oidresp = oidreq.answer(false)
			else
				session[:last_req] = oidreq
				redirect '/secret'
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

	get '/resume' do
		if session[:last_req]
			oidreq = session[:last_req]
			session[:last_req] = nil
			session[:user] = Secrets.user_value
			return respond(oidreq.answer(true))
		else
			return "Why am I here?"
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

	get '/user/' do
		"<html><head><link rel=\"openid2.provider\" href=\"#{request.base_url}/\" /></head><body>User</body></html>"
	end
end

class Private < Sinatra::Base
	get '/' do
		redirect '/resume'
	end

	def self.new(*)
		app = Rack::Auth::Digest::MD5.new(super) do |username|
			Secrets.password username
		end
		app.realm = 'OpenID Login'
		app.opaque = Secrets.opaque
		app
	end
end
