# Reverse Engineer's Hex Editor
# Copyright (C) 2017-2020 Daniel Collins <solemnwarning@solemnwarning.net>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

WX_CONFIG ?= wx-config
LLVM_CONFIG ?= llvm-config

EXE ?= rehex
EMBED_EXE ?= ./tools/embed

# Wrapper around the $(shell) function that aborts the build if the command
# exits with a nonzero status.
shell-or-die = \
	$(eval sod_out := $(shell $(1); echo $$?)) \
	$(if $(filter 0,$(lastword $(sod_out))), \
		$(wordlist 1, $(shell echo $$(($(words $(sod_out)) - 1))), $(sod_out)), \
		$(error $(1) exited with status $(lastword $(sod_out))))

WX_CXXFLAGS := $(call shell-or-die,$(WX_CONFIG) --cxxflags base core aui propgrid adv)
WX_LIBS     := $(call shell-or-die,$(WX_CONFIG) --libs     base core aui propgrid adv)

LLVM_COMPONENTS = $(call shell-or-die,$(LLVM_CONFIG) --components)

# The AArch64 disassembler prior to LLVM 8.0 crashes when used without a symbol
# lookup callback and doesn't properly handle a stub one which doesn't return a
# symbol name, so don't use it.

LLVM_VERSION_MAJOR = $(call shell-or-die,$(LLVM_CONFIG) --version | cut -d. -f1)
LLVM_AT_LEAST_V8 = $(shell [ $(LLVM_VERSION_MAJOR) -ge 8 ] && echo true)

ifeq "$(LLVM_AT_LEAST_V8)" "true"
	LLVM_ENABLE_AARCH64 ?= $(filter aarch64,$(LLVM_COMPONENTS))
endif

LLVM_ENABLE_ARM     ?= $(filter arm,$(LLVM_COMPONENTS))
LLVM_ENABLE_MIPS    ?= $(filter mips,$(LLVM_COMPONENTS))
LLVM_ENABLE_POWERPC ?= $(filter powerpc,$(LLVM_COMPONENTS))
LLVM_ENABLE_SPARC   ?= $(filter sparc,$(LLVM_COMPONENTS))
LLVM_ENABLE_X86     ?= $(filter x86,$(LLVM_COMPONENTS))

LLVM_USE_COMPONENTS := asmprinter
LLVM_DEFINES :=

ifneq "$(LLVM_ENABLE_AARCH64)" ""
	LLVM_USE_COMPONENTS += aarch64
	LLVM_DEFINES += -DLLVM_ENABLE_AARCH64
endif

ifneq "$(LLVM_ENABLE_ARM)" ""
	LLVM_USE_COMPONENTS += arm
	LLVM_DEFINES += -DLLVM_ENABLE_ARM
endif

ifneq "$(LLVM_ENABLE_MIPS)" ""
	LLVM_USE_COMPONENTS += mips
	LLVM_DEFINES += -DLLVM_ENABLE_MIPS
endif

ifneq "$(LLVM_ENABLE_POWERPC)" ""
	LLVM_USE_COMPONENTS += powerpc
	LLVM_DEFINES += -DLLVM_ENABLE_POWERPC
endif

ifneq "$(LLVM_ENABLE_SPARC)" ""
	LLVM_USE_COMPONENTS += sparc
	LLVM_DEFINES += -DLLVM_ENABLE_SPARC
endif

ifneq "$(LLVM_ENABLE_X86)" ""
	LLVM_USE_COMPONENTS += x86
	LLVM_DEFINES += -DLLVM_ENABLE_X86
endif

# I would use llvm-config --cxxflags, but that specifies more crap it has no
# business interfering with (e.g. warnings) than things it actually needs.
# Hopefully this is enough to get by everywhere.
LLVM_CXXFLAGS := -I$(call shell-or-die,$(LLVM_CONFIG) --includedir)
LLVM_LIBS     := $(call shell-or-die,$(LLVM_CONFIG) --ldflags --libs --system-libs $(LLVM_USE_COMPONENTS))

CFLAGS   := -Wall -std=c99   -ggdb -I. -Iinclude/ $(CFLAGS)
CXXFLAGS := -Wall -std=c++11 -ggdb -I. -Iinclude/ $(LLVM_CXXFLAGS) $(WX_CXXFLAGS) $(LLVM_DEFINES) $(CXXFLAGS)

LIBS := $(LLVM_LIBS) $(WX_LIBS) -ljansson $(LIBS)

ifeq ($(DEBUG),)
	DEBUG=0
endif

ifeq ($(DEBUG),0)
	CFLAGS   += -DNDEBUG
	CXXFLAGS += -DNDEBUG
else
	CFLAGS   += -g
	CXXFLAGS += -g
endif

VERSION    := Snapshot $(shell git log -1 --format="%H")
BUILD_DATE := $(shell date '+%F')

DEPDIR := .d
$(shell mkdir -p $(DEPDIR)/res/ $(DEPDIR)/src/ $(DEPDIR)/tools/ $(DEPDIR)/tests/ $(DEPDIR)/googletest/src/)
DEPFLAGS = -MT $@ -MMD -MP -MF $(DEPDIR)/$@.Td
DEPPOST = @mv -f $(DEPDIR)/$@.Td $(DEPDIR)/$@.d && touch $@

.PHONY: all
all: $(EXE)

.PHONY: check
check: tests/all-tests
	./tests/all-tests

.PHONY: clean
clean:
	rm -f res/license.c res/license.h res/icon16.c res/icon16.h res/icon32.c res/icon32.h res/icon48.c res/icon48.h res/icon64.c res/icon64.h res/icon128.c res/icon128.h
	rm -f $(APP_OBJS)
	rm -f $(EXE)
	rm -f $(TEST_OBJS)
	rm -f ./tests/all-tests
	rm -f $(EMBED_EXE)

APP_OBJS := \
	res/icon16.o \
	res/icon32.o \
	res/icon48.o \
	res/icon64.o \
	res/icon128.o \
	res/license.o \
	res/version.o \
	src/AboutDialog.o \
	src/app.o \
	src/buffer.o \
	src/ClickText.o \
	src/CodeCtrl.o \
	src/CommentTree.o \
	src/decodepanel.o \
	src/disassemble.o \
	src/document.o \
	src/LicenseDialog.o \
	src/mainwindow.o \
	src/Palette.o \
	src/search.o \
	src/SelectRangeDialog.o \
	src/textentrydialog.o \
	src/ToolPanel.o \
	src/util.o \
	src/win32lib.o \
	$(EXTRA_APP_OBJS)

$(EXE): $(APP_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

TEST_OBJS := \
	googletest/src/gtest-all.o \
	src/buffer.o \
	src/CommentTree.o \
	src/document.o \
	src/Palette.o \
	src/search.o \
	src/textentrydialog.o \
	src/ToolPanel.o \
	src/util.o \
	src/win32lib.o \
	tests/buffer.o \
	tests/CommentsDataObject.o \
	tests/CommentTree.o \
	tests/document.o \
	tests/main.o \
	tests/NestedOffsetLengthMap.o \
	tests/NumericTextCtrl.o \
	tests/search-bseq.o \
	tests/search-text.o \
	tests/SearchValue.o \
	tests/util.o

tests/all-tests: $(TEST_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

$(EMBED_EXE): tools/embed.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

src/AboutDialog.o: res/icon128.h
src/LicenseDialog.o: res/license.h
src/mainwindow.o: res/icon16.h res/icon32.h res/icon48.h res/icon64.h

res/license.c res/license.h: LICENSE.txt $(EMBED_EXE)
	$(EMBED_EXE) $< LICENSE_TXT res/license.c res/license.h

res/%.c res/%.h: res/%.png $(EMBED_EXE)
	$(EMBED_EXE) $< $*_png res/$*.c res/$*.h

.PHONY: res/version.o
res/version.o:
	$(CXX) $(CXXFLAGS) -DVERSION='"$(VERSION)"' -DBUILD_DATE='"$(BUILD_DATE)"' -c -o $@ res/version.cpp

%.o: %.c
	$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<
	$(DEPPOST)

tests/%.o: tests/%.cpp
	$(CXX) $(CXXFLAGS) -I./googletest/include/ $(DEPFLAGS) -c -o $@ $<
	$(DEPPOST)

googletest/src/%.o: googletest/src/%.cc
	$(CXX) $(CXXFLAGS) -I./googletest/include/ -I./googletest/ $(DEPFLAGS) -c -o $@ $<
	$(DEPPOST)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(DEPFLAGS) -c -o $@ $<
	$(DEPPOST)

include $(shell find .d/ -name '*.d' -type f)

prefix      ?= /usr/local
bindir      ?= $(prefix)/bin
datarootdir ?= $(prefix)/share

.PHONY: install
install: $(EXE)
	install -D -m 0755 $(EXE) $(DESTDIR)$(bindir)/$(EXE)
	
	for s in 16 32 48 64 128 256 512; \
	do \
		install -D -m 0644 res/icon$${s}.png $(DESTDIR)$(datarootdir)/icons/hicolor/$${s}x$${s}/apps/rehex.png; \
	done
	
	install -D -m 0644 res/rehex.desktop $(DESTDIR)$(datarootdir)/applications/rehex.desktop

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)$(bindir)/$(EXE)
	rm -f $(DESTDIR)$(datarootdir)/applications/rehex.desktop
	
	for s in 16 32 48 64 128 256 512; \
	do \
		rm -f $(DESTDIR)$(datarootdir)/icons/hicolor/$${s}x$${s}/apps/rehex.png; \
	done
