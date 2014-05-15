require 'sinatra'
require 'openid'
require 'openid/store/filesystem'

include OpenID::Server

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
		[302, {:Location => web_response.headers['location']}, web_response.body]
	else
		[400, web_response.body]
	end
end

def handle(params)
	begin
		oidreq = server.decode_request(params)
	rescue ProtocolError => e
		return [500, e.to_s]
	end

	oidresp = nil
	if oidreq.kind_of?(CheckIDRequest)
		if (oidreq.id_select)
			oidresp = oidreq.answer(false)
		else
			oidresp = oidreq.answer(true)
		end
	else
		oidresp = server.handle_request(oidreq)
	end

	respond(oidresp)
end

get '/' do
	handle(params)
end

post '/' do
	handle(params)
end

get '/user/' do
	'<html><head><link rel="openid2.provider" href="http://localhost:4567/" /></head><body>User</body></html>'
end
