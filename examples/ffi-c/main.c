#include "inez/inez.h"
#include <stdbool.h>
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc < 4) {
    return 1;
  }

  int status = 0;

  const char *path = argv[1];
  const char *section = argv[2];
  const char *key = argv[3];

  InezContext *ctx = inezInit(1024 * 1024 * 10);
  char value_buf[64] = {0};

  if (!ctx) {
    fprintf(stderr, "error: inez init failed\n");
    status = 1;
    goto cleanup;
  }

  if (!inezLoadFile(ctx, path)) {
    inezLogLastError(ctx);
    status = 1;
    goto cleanup;
  }

  if (!inezParse(ctx)) {
    inezLogLastError(ctx);
    status = 1;
    goto cleanup;
  }

  if (!inezGet(ctx, section, key, value_buf, 64)) {
    inezLogLastError(ctx);
    status = 1;
    goto cleanup;
  }

  printf("%s:%s = %s\n", section, key, value_buf);

cleanup:
  if (ctx) {
    inezDeinit(ctx);
  }

  return status;
}
