.PHONY: zig
zig:
	zig build run

.PHONY: doc
doc:buildDoc
	python3 -m http.server 6969 -d "./zig-out/docs"

.PHONY: buildDoc
buildDoc:
	zig build docs
