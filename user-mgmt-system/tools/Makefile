CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -std=c11
TARGET   = passwd_checker

all: $(TARGET)

$(TARGET): passwd_checker.c
	$(CC) $(CFLAGS) -o $(TARGET) passwd_checker.c

clean:
	rm -f $(TARGET)

.PHONY: all clean
