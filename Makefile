doc:buildDoc
	python3 -m http.server 6969 -d "./zig-out/docs"
buildDoc:
	zig build docs
