# -*- coding:utf-8 -*-

# _____________________________________________________________________________
#                                                                       Imports

# Standard libraries.
from enum import IntEnum
from libc.stdint cimport uint32_t
from libc.stdlib cimport malloc, free
from cpython cimport Py_buffer, PyBuffer_Release
from cpython.unicode cimport PyUnicode_Check

# Local imports.
from pcre2._libs.libpcre2 cimport *
from pcre2.exceptions cimport raise_from_rc
from pcre2._utils.strings cimport (
    get_buffer, codeunit_to_codepoint
)
from pcre2.match cimport Match


# _____________________________________________________________________________
#                                                                     Constants

class CompileOption(IntEnum):
    ANCHORED = PCRE2_ANCHORED
    NO_UTF_CHECK = PCRE2_NO_UTF_CHECK
    ENDANCHORED = PCRE2_ENDANCHORED
    ALLOW_EMPTY_CLASS = PCRE2_ALLOW_EMPTY_CLASS
    ALT_BSUX = PCRE2_ALT_BSUX
    AUTO_CALLOUT = PCRE2_AUTO_CALLOUT
    CASELESS = PCRE2_CASELESS
    DOLLAR_ENDONLY = PCRE2_DOLLAR_ENDONLY
    DOTALL = PCRE2_DOTALL
    DUPNAMES = PCRE2_DUPNAMES
    EXTENDED = PCRE2_EXTENDED
    FIRSTLINE = PCRE2_FIRSTLINE
    MATCH_UNSET_BACKREF = PCRE2_MATCH_UNSET_BACKREF
    MULTILINE = PCRE2_MULTILINE
    NEVER_UCP = PCRE2_NEVER_UCP
    NEVER_UTF = PCRE2_NEVER_UTF
    NO_AUTO_CAPTURE = PCRE2_NO_AUTO_CAPTURE
    NO_AUTO_POSSESS = PCRE2_NO_AUTO_POSSESS
    NO_DOTSTAR_ANCHOR = PCRE2_NO_DOTSTAR_ANCHOR
    NO_START_OPTIMIZE = PCRE2_NO_START_OPTIMIZE
    UCP = PCRE2_UCP
    UNGREEDY = PCRE2_UNGREEDY
    UTF = PCRE2_UTF
    NEVER_BACKSLASH_C = PCRE2_NEVER_BACKSLASH_C
    ALT_CIRCUMFLEX = PCRE2_ALT_CIRCUMFLEX
    ALT_VERBNAMES = PCRE2_ALT_VERBNAMES
    USE_OFFSET_LIMIT = PCRE2_USE_OFFSET_LIMIT
    EXTENDED_MORE = PCRE2_EXTENDED_MORE
    LITERAL = PCRE2_LITERAL
    MATCH_INVALID_UTF = PCRE2_MATCH_INVALID_UTF


    @classmethod
    def verify(cls, options):
        """ Verify a number is composed of compile options.
        """
        tmp = options
        for opt in cls:
            tmp ^= (opt & tmp)
        return tmp == 0


    @classmethod
    def decompose(cls, options):
        """ Decompose a number into its components compile options.

        Return a list of CompileOption enums that are components of the given
        optins. Note that left over bits are ignored, and veracity can not be
        determined from the result.
        """
        return [opt for opt in cls if (opt & options)]


class SubstituteOption(IntEnum):
    # Option flags shared with matching.
    NOTBOL = PCRE2_NOTBOL
    NOTEOL = PCRE2_NOTEOL
    NOTEMPTY = PCRE2_NOTEMPTY
    NOTEMPTY_ATSTART = PCRE2_NOTEMPTY_ATSTART
    PARTIAL_SOFT = PCRE2_PARTIAL_SOFT
    PARTIAL_HARD = PCRE2_PARTIAL_HARD
    NO_JIT = PCRE2_NO_JIT

    # Substitute only flags.
    GLOBAL = PCRE2_SUBSTITUTE_GLOBAL
    EXTENDED = PCRE2_SUBSTITUTE_EXTENDED
    UNSET_EMPTY = PCRE2_SUBSTITUTE_UNSET_EMPTY
    UNKNOWN_UNSET = PCRE2_SUBSTITUTE_UNKNOWN_UNSET
    OVERFLOW_LENGTH = PCRE2_SUBSTITUTE_OVERFLOW_LENGTH
    LITERAL = PCRE2_SUBSTITUTE_LITERAL
    REPLACEMENT_ONLY = PCRE2_SUBSTITUTE_REPLACEMENT_ONLY


    @classmethod
    def verify(cls, options):
        """ Verify a number is composed of substitute options.
        """
        tmp = options
        for opt in cls:
            tmp ^= (opt & tmp)
        return tmp == 0


    @classmethod
    def decompose(cls, options):
        """ Decompose a number into its components substitute options.

        Return a list of CompileOption enums that are components of the given
        optins. Note that left over bits are ignored, and veracity can not be
        determined from the result.
        """
        return [opt for opt in cls if (opt & options)]


class BsrChar(IntEnum):
    UNICODE = PCRE2_BSR_UNICODE
    ANYCRLF = PCRE2_BSR_ANYCRLF


class NewlineChar(IntEnum):
    CR = PCRE2_NEWLINE_CR
    LF = PCRE2_NEWLINE_LF
    CRLF = PCRE2_NEWLINE_CRLF
    ANY = PCRE2_NEWLINE_ANY
    ANYCRLF = PCRE2_NEWLINE_ANYCRLF
    NUL = PCRE2_NEWLINE_NUL


# _____________________________________________________________________________
#                                                                 Pattern class

cdef class Pattern:
    """

    Attributes:

        See pattern.pxd for attribute definitions.
        Dynamic attributes are enabled for this class.

        code: Compiled PCRE2 code.
        options: PCRE2 compilation options.
        pattern: Buffer containing source pattern expression including byte
            string and a reference to source object.
    """

    
    # _________________________________________________________________
    #                                    Lifetime and memory management

    def __cinit__(self):
        self._code = NULL
        self._patn = NULL
        self._opts = 0


    def __init__(self, *args, **kwargs):
        # Prevent accidental instantiation from normal Python code since we
        # cannot pass pointers into a Python constructor.
        module = self.__class__.__module__
        qualname = self.__class__.__qualname__
        raise TypeError(f"Cannot create '{module}.{qualname}' instances.")


    def __dealloc__(self):
        if self._patn is not NULL:
            PyBuffer_Release(self._patn)
        if self._code is not NULL:
            pcre2_code_free(self._code)


    @staticmethod
    cdef Pattern _from_data(pcre2_code_t *code, Py_buffer *patn, uint32_t opts):
        """ Factory function to create Pattern objects from C-type fields.

        The ownership of the given pointers are stolen, which causes the
        extension type to free them when the object is deallocated.
        """

        # Fast call to __new__() that bypasses the __init__() constructor.
        cdef Pattern pattern = Pattern.__new__(Pattern)
        pattern._code = code
        pattern._patn = patn
        pattern._opts = opts
        return pattern


    # _________________________________________________________________
    #                                               Pattern information


    cdef uint32_t _pcre2_pattern_info_uint(self, uint32_t what):
        """ Safely access pattern info returned as uint32_t. 
        """
        cdef int pattern_info_rc
        cdef uint32_t where
        pattern_info_rc = pcre2_pattern_info(self._code, what, &where)
        if pattern_info_rc < 0:
            raise_from_rc(pattern_info_rc, None)
        return where


    cdef bint _pcre2_pattern_info_bint(self, uint32_t what):
        """ Safely access pattern info returned as bint. 
        """
        cdef int pattern_info_rc
        cdef bint where
        pattern_info_rc = pcre2_pattern_info(self._code, what, &where)
        if pattern_info_rc < 0:
            raise_from_rc(pattern_info_rc, None)
        return where


    @property
    def pattern(self):
        """ Return the pattern the object was compiled with.
        """
        return self._patn.obj

    
    @property
    def options(self):
        """ Return the options the object was compiled with.
        """
        return self._opts


    @property
    def all_options(self):
        """ Returns the compile options as modified by any top-level (*XXX)
        option settings such as (*UTF) at the start of the pattern itself.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_ALLOPTIONS)


    @property
    def backref_max(self):
        """ Return the number of the highest backreference in the pattern.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_BACKREFMAX)


    @property
    def backslash_r(self):
        """ Return an indicator to what character sequences the \R escape
        sequence matches.
        """
        cdef uint32_t bsr
        bsr = self._pcre2_pattern_info_uint(PCRE2_INFO_BSR)
        return BsrChar(bsr)


    @property
    def capture_count(self):
        """ Return the highest capture group number in the pattern. In patterns
        where (?| is not used, this is also the total number of capture groups.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_CAPTURECOUNT)


    @property
    def depth_limit(self):
        """ If the pattern set a backtracking depth limit by including an item
        of the form (*LIMIT_DEPTH=nnnn) at the start, the value is returned. 
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_DEPTHLIMIT)


    @property
    def has_blackslash_c(self):
        """ Return True if the pattern contains any instances of \C, otherwise
        False. 
        """
        return self._pcre2_pattern_info_bint(PCRE2_INFO_HASBACKSLASHC)


    @property
    def has_crorlf(self):
        """ Return True if the pattern contains any explicit matches for CR or
        LF characters, otherwise False. 
        """
        return self._pcre2_pattern_info_bint(PCRE2_INFO_HASCRORLF)


    @property
    def j_changed(self):
        """ Return True if the (?J) or (?-J) option setting is used in the
        pattern, otherwise False. 
        """
        return self._pcre2_pattern_info_bint(PCRE2_INFO_JCHANGED)


    @property
    def jit_size(self):
        """ If the compiled pattern was successfully JIT compiled, return the
        size of the JIT compiled code, otherwise return zero.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_JITSIZE)
    

    @property
    def match_empty(self):
        """ Return True if the pattern might match an empty string, otherwise
        False.
        """
        return self._pcre2_pattern_info_bint(PCRE2_INFO_MATCHEMPTY)


    @property
    def match_limit(self):
        """ If the pattern set a match limit by including an item of the form
        (*LIMIT_MATCH=nnnn) at the start, the value is returned. 
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_MATCHLIMIT)


    @property
    def max_lookbehind(self):
        """ A lookbehind assertion moves back a certain number of characters
        (not code units) when it starts to process each of its branches. This
        request returns the largest of these backward moves.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_MAXLOOKBEHIND)


    @property
    def min_length(self):
        """ If a minimum length for matching subject strings was computed, its
        value is returned. Otherwise the returned value is 0. This value is not
        computed when CompileOption.NO_START_OPTIMIZE is set.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_MINLENGTH)

    
    @property
    def name_count(self):
        """ Returns the number of named capture groups.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_NAMECOUNT)


    @property
    def newline(self):
        """ Returns the type of character sequence that will be recognized as 
        meaning "newline" while matching.
        """
        cdef uint32_t newline
        newline = self._pcre2_pattern_info_uint(PCRE2_INFO_NEWLINE)
        return NewlineChar(newline)


    @property
    def size(self):
        """ Return the size of the compiled pattern in bytes.
        """
        return self._pcre2_pattern_info_uint(PCRE2_INFO_SIZE)


    def name_dict(self):
        """ Dictionary from capture group index to capture group name.
        """
        # Get name table related information.
        cdef uint32_t name_count
        cdef uint32_t name_entry_size
        name_count = self._pcre2_pattern_info_uint(PCRE2_INFO_NAMECOUNT)
        name_entry_size = self._pcre2_pattern_info_uint(PCRE2_INFO_NAMEENTRYSIZE)

        cdef pcre2_sptr_t name_table
        pattern_info_rc = pcre2_pattern_info(self._code, PCRE2_INFO_NAMETABLE, &name_table)
        if pattern_info_rc < 0:
            raise_from_rc(pattern_info_rc, None)

        # Convert byte table to dictionary.
        cdef uint32_t i
        cdef uint32_t offset
        name_dict = {}
        for i in range(name_count):
            offset = i * name_entry_size
            # First two bytes of name table contain index, followed by possibly
            # unicode byte string.
            entry_idx = int((name_table[offset] << 8) | name_table[offset + 1])
            entry_name = name_table[offset + 2:offset + name_entry_size]

            # Clean up entry and convert to unicode as appropriate.
            entry_name = entry_name.strip(b"\x00")
            if PyUnicode_Check(self._patn.obj):
                entry_name = entry_name.decode("utf-8")

            name_dict[entry_idx] = entry_name

        return name_dict


    # _________________________________________________________________
    #                                                           Methods

    def match(self, object subject, uint32_t options=0):
        # Only allow for same type comparisons.
        if PyUnicode_Check(subject) and not PyUnicode_Check(self._patn.obj):
            raise ValueError("Cannot use a unicode pattern on a bytes-like object.")

        elif not PyUnicode_Check(subject) and PyUnicode_Check(self._patn.obj):
            raise ValueError("Cannot use a bytes-like pattern on a unicode object.")

        # Attempt match of pattern onto subject.
        cdef Py_buffer *subj = get_buffer(subject)
        mtch = pcre2_match_data_create_from_pattern(
            self._code,
             NULL
        )
        if not mtch:
            raise MemoryError()
        
        cdef int match_rc = pcre2_match(
            self._code,
            <pcre2_sptr_t>subj.buf,
            <size_t>subj.len,
            0, # Start offset.
            options,
            mtch,
            NULL
        )
        if match_rc < 0:
            raise_from_rc(match_rc, None)
            
        return Match._from_data(mtch, self, subj, options)


    def jit_compile(self, args):
        pass


    def substitute(self, args):
        pass