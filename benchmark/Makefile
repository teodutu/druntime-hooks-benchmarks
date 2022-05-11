CFLAGS ?= -release -O -boundscheck=off
BENCHMARK=benchmark

all: $(BENCHMARK).d
	$(CC) $(CFLAGS) $(BENCHMARK).d

clean:
	-rm -f $(BENCHMARK) *.o

.PHONY: all clean
