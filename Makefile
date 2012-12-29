
ALL_FILES      := $(wildcard *.d)
INTERP_FILES   := interp.d
COMPILER_FILES := $(filter-out $(INTERP_FILES),$(ALL_FILES))

all: bfc bfi

bfi: $(INTERP_FILES)
	dmd -gc $^ -of$@

bfc: $(COMPILER_FILES)
	dmd -gc $^ -of$@


.PHONY: clean
clean:
	-rm *.o bfc bfi
