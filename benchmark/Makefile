CFLAGS ?= -release -O -boundscheck=off
BENCHMARK = array_benchmark

all: $(BENCHMARK).d
	$(CC) $(CFLAGS) $(BENCHMARK).d

clean:
	-rm -f $(BENCHMARK) *.o

.PHONY: all clean
