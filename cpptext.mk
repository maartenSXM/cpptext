# cpptext.mk is from https://github.com/maartenSXM/cpptext.
#
# This file is intended to be included from your project Makefile and
# depends on $(CPT_HOME) being a git clone of github.com/maartenSXM/cpptext.
#
# See https://github.com/maartenSXM/cpptext/blob/main/Makefile for
# an example of how to automatically setup this repo as a submodule
# and include this file from a Makefile.
#
# Refer to https://github.com/maartenSXM/cpptext/blob/main/README.md
# for more details.

MAKEFLAGS    += --no-builtin-rules
MAKEFLAGS    += --no-builtin-variables
MAKECMDGOALS ?= all

# These can be optionally overridden in a project Makefile that
# includes this cpptext.mk file. 

# set some defaults for unset simply expanded variables

ifeq (,$(CPT_HOME))
CPT_HOME := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
ifeq (,$(CPT_BUILD_DIR))
CPT_BUILD_DIR := build
endif
ifeq (,$(CPT_TMP_SUBDIR))
CPT_TMP_SUBDIR := dehashed
endif

# Use these overrides to specify dependencies that customize the build
CPT_PRE_TGT  ?= 
CPT_MAIN_TGT ?= cppTgt
CPT_POST_TGT ?= 

# automatically
ifeq (,$(findstring esphome,$(VIRTUAL_ENV)))
endif

# Use these to specify dependicies that customize cleaning.  This inializes them.
CPT_EXTRA_CLEAN_TGT    := $(if $(CPT_EXTRA_CLEAN_TGT),$(CPT_EXTRA_CLEAN_TGT),)
CPT_EXTRA_REALCLEAN_TGT:= $(if $(CPT_EXTRA_REALCLEAN_TGT),$(CPT_EXTRA_REALCLEAN_TGT),)

ifeq ($(CPT_SRCS),)
  $(error "set CPT_SRCS to the files you want to run dehash.sh on")
endif

ifeq ($(CPT_GEN),)
  $(error "set CPT_GEN to the files you want to run cpp on")
endif

ifeq ($(shell which gcc),)
  $(error "gcc not found. Please install it")
endif

ifeq (,$(findstring GNU,$(shell sed --version 2>/dev/null)))
  ifeq (,$(shell which gsed))
    $(error "GNU sed not found. Please install it")
  else
    SED=gsed
  endif
else
    SED=sed
endif

ifeq ($(CPT_BUILD_DIR),.)
  $(error "CPT_BUILD_DIR set to . is not supported.")
endif

CPT_TMP_DIR  := $(CPT_BUILD_DIR)/$(CPT_TMP_SUBDIR)
CPT_DEHASH   := $(CPT_HOME)/dehash.sh --cpp
CPT_INFILES  := $(sort $(patsubst ./%,%,$(CPT_SRCS)))
CPT_OUTFILES := $(addprefix $(CPT_BUILD_DIR)/,$(patsubst ./%,%,$(CPT_GEN)))

CPT_CPPFLAGS := -x c -E -P -undef -Wundef -Werror -nostdinc \
		 $(CPT_EXTRA_FLAGS)

# setup #includes so that all dehashed source directories come first,
# followed by all source directories. Thus, includes of yaml files will
# include the dehashes variants of the file and includes of non-yaml
# files such as images will come from the source tree.

CPT_CPPINCS   := -I $(CPT_TMP_DIR)					\
	         $(foreach d,$(patsubst %/,%,				\
		   $(sort $(dir $(CPT_SRCS)))),-I $(CPT_TMP_DIR)/$(d))	\
	         $(foreach d,$(patsubst %/,%,				\
		   $(sort $(dir $(CPT_SRCS)))),-I $(d))			\
		 $(CPT_EXTRA_INCS)

CPT_CPPDEFS   := -D CPT_USER_$(USER)=1 -D CPT_USER=$(USER)   \
	       $(CPT_EXTRA_DEFS)

CPT_CPP	= gcc $(CPT_CPPFLAGS) $(CPT_CPPINCS) $(CPT_CPPDEFS) 

# CPT_TMP_SRCS is the list of dehashed files in CPT_TMP_DIR
CPT_TMP_SRCS = $(addprefix $(CPT_TMP_DIR)/, \
		 $(sort $(patsubst ./%,%,$(CPT_INFILES))))

# create all build directories (sort filters duplicates)
CPT_MKDIRS := $(sort $(CPT_BUILD_DIR)		\
		     $(CPT_TMP_DIR)		\
		     $(dir $(CPT_TMP_SRCS))	\
		     $(dir $(CPT_OUTFILES)))

$(shell mkdir -p $(CPT_MKDIRS))

# skip include of esphome.mk by defining CPT_NO_ESPHOME to non-empty
ifeq (,$(CPT_NO_ESPHOME))
  # include esphome.mk if ESP_INIT is defined
  ifneq (,$(ESP_INIT))
    CPT_MAIN_TGT = esphomeTgt
    include $(CPT_HOME)/esphome.mk
  endif
endif

all: $(CPT_PRE_TGT) $(CPT_MAIN_TGT) $(CPT_POST_TGT) 

define _uptodate
  printf "cpptext.mk: $(1) is up to date.\n";
endef

cppTgt: $(CPT_INFILES) $(CPT_OUTFILES)
	@$(foreach tgt,$(notdir $(CPT_OUTFILES)),$(call _uptodate,$(tgt)))

$(CPT_INFILES):
	$(error source file $@ does not exist)

# Emit the rules that run cpp to generate all the CPT_OUTFILES

define _cpp
$(CPT_BUILD_DIR)/$(1): $(CPT_TMP_DIR)/$(1) $(CPT_TMP_SRCS)
	$(CPT_CPP) -MD -MP -MT $$@ -MF $$<.d $$< -o $$@
	$(CPT_CPP_MORE)
endef
$(foreach src,$(patsubst ./%,%,$(CPT_GEN)),$(eval $(call _cpp,$(src))))

# Emit the rules that dehash the sources into the project directory

define _dehash
$(CPT_TMP_DIR)/$(1): $(1)
	@printf "Dehashing to $$@\n"
	@$(CPT_DEHASH) $$< >$$@
endef

$(foreach src,$(patsubst ./%,%,$(CPT_INFILES)), $(eval $(call _dehash,$(src))))

# Include the dependency rules generated from a previous build, if any

-include $(wildcard $(CPT_TMP_DIR)/*.d)

clean: $(CPT_EXTRA_CLEAN_TGT)
	rm -rf $(CPT_TMP_DIR) $(CPT_OUTFILES) $(CPT_CLEAN_FILES)
	$(CPT_CLEAN_MORE)

realclean: clean $(CPT_EXTRA_REALCLEAN_TGT)
	-@if [ "`git -C $(CPT_HOME) status --porcelain`" != "" ]; then	\
		printf "$(CPT_HOME) not porcelain. Leaving it.\n";	\
	else								\
		echo rm -rf $(CPT_HOME);				\
		rm -rf $(CPT_HOME);					\
	fi
	rm -rf $(CPT_TMP_DIR) $(CPT_REALCLEAN_FILES)
	$(CPT_REALCLEAN_MORE)

define _print_defaults
print-defaults:: cppTgt $(CPT_TMP_DIR)/$(1)
	@printf "Default values for $(1)\n"
	@$(CPT_CPP) -CC $(CPT_TMP_DIR)/$(1) | \
		grep '^//#default' | $(SED) 's/^../  /'
endef

$(foreach gen,$(patsubst ./%,%,$(CPT_GEN)), \
    $(eval $(call _print_defaults,$(gen))))

.PRECIOUS: $(CPT_TMP_DIR) $(CPT_BUILD_DIR) $(CPT_HOME)
.PHONY: all clean realclean mkdirs cppTgt print-defaults \
		    $(CPT_PRE_TGT) $(CPT_MAIN_TGT) $(CPT_POST_TGT)

