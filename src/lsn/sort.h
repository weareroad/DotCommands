#ifndef _SORT_H
#define _SORT_H

typedef int (*cmpfilfunc_t)(const void *a, const void *b);

#ifndef NONONO

extern int sort_cmp_file_by_name(const void *a, const void *b);
extern int sort_cmp_file_by_time(const void *a, const void *b);
extern int sort_cmp_file_by_size(const void *a, const void *b);
extern int sort_cmp_file_by_extension(const void *a, const void *b);

extern int sort_cmp_option(const void *a, const void *b);
extern int sort_opt_search(const void *name, const void *a);

#endif

#endif
