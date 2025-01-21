#ifndef INEZ_H
#define INEZ_H

#include <stdbool.h>
#include <stddef.h>

typedef void InezContext;

InezContext *inezInit(size_t max_read_size);

void inezDeinit(InezContext *ctx);

void inezLogLastError(InezContext *ctx);

void inezLoadBuffer(InezContext *ctx, const char *buf);

void inezLoadBufferOwned(InezContext *ctx, const char *buf, size_t buf_len);

bool inezLoadFile(InezContext *ctx, const char *path);

bool inezParse(InezContext *ctx);

bool inezGet(InezContext *ctx, const char *section, const char *key, char *buf,
             size_t buf_len);

#endif // INEZ_H
