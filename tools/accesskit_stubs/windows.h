/* Minimal stub used by tools/generate_accesskit_bindings.py so accesskit.h
   can be parsed on any host without the real Windows SDK. Only the types
   referenced by accesskit.h are defined. */
#ifndef ACCESSKIT_STUB_WINDOWS_H
#define ACCESSKIT_STUB_WINDOWS_H

typedef void *HWND;
typedef long long LRESULT;
typedef unsigned long long WPARAM;
typedef long long LPARAM;

#endif
