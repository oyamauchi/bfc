
ROOT_FILES     := $(wildcard *.d)
OPTIMIZE_FILES := $(wildcard optimize/*.d)
ALL_FILES      := $(ROOT_FILES) $(OPTIMIZE_FILES)

INTERP_FILES   := interp.d
COMPILER_FILES := $(filter-out $(INTERP_FILES),$(ALL_FILES))

all: bfc bfi

bfi: $(INTERP_FILES)
	dmd -gc $^ -of$@

bfc: $(COMPILER_FILES)
	dmd -gc $^ -of$@


.PHONY: clean
clean:
	-rm -f *.o bfc bfi
