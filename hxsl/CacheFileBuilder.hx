package hxsl;

enum CacheFilePlatform {
	DirectX;
	OpenGL;
	PS4;
}

private class CustomCacheFile extends CacheFile {

	var build : CacheFileBuilder;
	var shared : Map<String,SharedShader> = new Map();

	public function new(build) {
		this.build = build;
		super(true, true);
	}

	override function addSource(r:RuntimeShader) {
		r.vertex.code = build.compileShader(r, r.vertex);
		r.fragment.code = build.compileShader(r, r.fragment);
		super.addSource(r);
	}

	override function resolveShader(name:String):hxsl.Shader {
		var s = super.resolveShader(name);
		if( s != null )
			return s;
		var shared = shared.get(name);
		if( shared == null ) {
			var src = build.shaderLib.get(name);
			if( src == null )
				return null;
			shared = new SharedShader(src);
			this.shared.set(name, shared);
		}
		return new hxsl.DynamicShader(shared);
	}

	override function getPlatformTag() {
		return switch( build.platform ) {
		case DirectX: "dx";
		case OpenGL: "gl";
		case PS4: "ps4";
		};
	}

}

class CacheFileBuilder {

	public var platform : CacheFilePlatform;
	public var platforms : Array<CacheFilePlatform> = [];
	public var shaderLib : Map<String,String> = new Map();
	public var dxInitDone = false;
	public var dxShaderVersion = "5_0";

	public function new() {
	}

	public function run() {
		for( p in platforms ) {
			Sys.println("Generating shaders for " + p);
			this.platform = p;
			var cache = new CustomCacheFile(this);
			@:privateAccess cache.save();
		}
	}

	function binaryPayload( data : haxe.io.Bytes ) {
		return "\nBIN=" + haxe.crypto.Base64.encode(data) + "#";
	}

	public function compileShader( r : RuntimeShader, rd : RuntimeShader.RuntimeShaderData ) : String {
		Sys.print(".");
		switch( platform ) {
		case DirectX:
			#if hldx
			if( !dxInitDone ) {
				var win = new dx.Window("", 800, 600);
				win.visible = false;
				dxInitDone = true;
				dx.Driver.create(win, R8G8B8A8_UNORM, None);
			}
			var out = new HlslOut();
			var code = out.run(rd.data);
			var bytes = dx.Driver.compileShader(code, "", "main", (rd.vertex?"vs_":"ps_") + dxShaderVersion, OptimizationLevel3);
			return code + binaryPayload(bytes);
			#else
			throw "DirectX compilation requires -lib hldx";
			#end
		case OpenGL:
			var out = new GlslOut();
			out.version = 150;
			return out.run(rd.data);
		case PS4:
			#if hlps
			var out = new ps.gnm.PsslOut();
			var code = out.run(rd.data);
			var tmpFile = "tmp";
			var tmpSrc = tmpFile + ".pssl";
			var tmpOut = tmpFile + ".sb";
			sys.io.File.saveContent(tmpSrc, code);
			var args = ["-profile", rd.vertex ? "sce_vs_vs_orbis" : "sce_ps_orbis", "-o", tmpOut, tmpSrc];
			var p = new sys.io.Process("orbis-wave-psslc.exe", args);
			var error = p.stderr.readAll().toString();
			var ecode = p.exitCode();
			if( ecode != 0 )
				throw "ERROR while compiling " + tmpSrc + "\n" + error;
			p.close();
			var data = sys.io.File.getBytes(tmpOut);
			sys.FileSystem.deleteFile(tmpSrc);
			sys.FileSystem.deleteFile(tmpOut);
			return code + binaryPayload(data);
			#else
			throw "PS4 compilation requires -lib hlps";
			#end
		}
		throw "Missing implementation for " + platform;
	}

	public static function main() {
		var args = Sys.args();
		try sys.FileSystem.deleteFile("hxsl.CacheFileBuilder.hl") catch( e : Dynamic ) {};
		var builder = new CacheFileBuilder();
		while( args.length > 0 ) {
			var f = args.shift();
			var pos = f.indexOf("=");
			if( pos > 0 ) {
				args.unshift(f.substr(pos + 1));
				f = f.substr(0, pos);
			}
			function getArg() {
				if( args.length == 0 ) throw f + " requires argument";
				return args.shift();
			}
			switch( f ) {
			case "-file":
				CacheFile.FILENAME = getArg();
			case "-lib":
				var lib = new format.hl.Reader().read(new haxe.io.BytesInput(sys.io.File.getBytes(getArg())));
				var r_shader = ~/^oy4:namey([0-9]+):/;
				for( s in lib.strings ) {
					if( !r_shader.match(s) ) continue;
					var len = Std.parseInt(r_shader.matched(1));
					var name = r_shader.matchedRight().substr(0, len);
					builder.shaderLib.set(name, s);
				}
			case "-gl":
				builder.platforms.push(OpenGL);
			case "-dx":
				builder.platforms.push(DirectX);
			case "-ps4":
				builder.platforms.push(PS4);
			default:
				throw "Unknown parameter " + f;
			}
		}
		builder.run();
	}

}