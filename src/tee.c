#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define BUFFER_SIZE 4096

int main(int argc, char *argv[]) {
  int opt;
  _Bool append = 0;

  // Parse args
  while ((opt = getopt(argc, argv, "ai")) != -1) {
    switch (opt) {
    case 'a':
      append = 1;
      break;
    case 'i': {
      struct sigaction sa = {.sa_handler = SIG_IGN};
      sigaction(SIGINT, &sa, NULL);
    } break;
    case '?':
      fprintf(stderr, "Usage: %s [-ai] [file ...]\n", argv[0]);
      return 1;
    default:
      abort();
    }
  }

  int num_files = argc - optind;
  int *fds = malloc(num_files * sizeof(int));
  int flags = O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC);
  int exit_status = 0;

  // Open files
  for (int i = 0; i < num_files; ++i) {
    fds[i] = open(argv[optind + i], flags, 0664);
    if (fds[i] < 0) {
      perror(argv[optind + i]);
      exit_status = 1;
    }
  }

  char buf[BUFFER_SIZE];
  ssize_t bytes_read;

  while ((bytes_read = read(STDIN_FILENO, buf, BUFFER_SIZE)) > 0 ||
         (bytes_read < 0 && errno == EINTR)) {
    if (bytes_read < 0) {
      continue;
    }

    if (write(STDOUT_FILENO, buf, bytes_read) < 0) {
      perror("stdout");
      exit_status = 1;
    }

    for (int i = 0; i < num_files; ++i) {
      if (fds[i] >= 0) {
        if (write(fds[i], buf, bytes_read) < 0) {
          perror(argv[optind + i]);
          exit_status = 1;
        }
      }
    }
  }

  if (bytes_read < 0) {
    perror("read stdin");
    exit_status = 1;
  }

  // Clean up
  for (int i = 0; i < num_files; i++) {
    if (fds[i] >= 0) {
      close(fds[i]);
    }
  }
  free(fds);

  return exit_status;
}
