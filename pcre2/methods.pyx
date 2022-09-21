# -*- coding:utf-8 -*-

# Standard libraries.
from libc.stdint cimport uint32_t
from cpython cimport Py_buffer
from cpython.unicode cimport PyUnicode_Check

# Local imports.
from .utils cimport *
from .libpcre2 cimport *
from .pattern cimport Pattern
from .match cimport Match


def compile(pattern, options=0):
    """ Factory function to create Pattern objects with newly compiled
    pattern.
    """
    
    cdef Py_buffer *patn = get_buffer(pattern)
    cdef uint32_t opts = <uint32_t>options

    # Ensure unicode strings are processed with UTF-8 support.
    if PyUnicode_Check(pattern):
        options = options | PCRE2_UTF | PCRE2_NO_UTF_CHECK

    cdef int compile_rc
    cdef size_t compile_errpos
    cdef pcre2_code_t *code = pcre2_compile(
        <pcre2_sptr_t>patn.buf, <size_t>patn.len, opts, &compile_rc, &compile_errpos, NULL
    )

    if code is NULL:
        # If source was a unicode string, use the code point offset.
        if PyUnicode_Check(pattern):
            _, compile_errpos = codeunit_to_codepoint(patn, compile_errpos, 0, 0)
        additional_msg = f"Compilation failed at position {compile_errpos!r}."
        raise_from_rc(compile_rc, additional_msg)

    return Pattern._from_data(code, patn, opts)


def match(pattern, subject, offset=0, options=0):
    return compile(pattern).match(subject, offset=offset, options=options)


def scan(pattern, subject, offset=0):
    return compile(pattern).scan(subject, offset=offset)


def substitute(pattern, replacement, subject, offset=0, options=0, low_memory=False):
    return compile(pattern).substitute(
        replacement, subject, offset=offset, options=options, low_memory=low_memory
    )