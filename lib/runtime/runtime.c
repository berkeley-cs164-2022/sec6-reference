#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

extern uint64_t lisp_entry(void *heap);

#define num_mask 0b11
#define num_tag 0b00
#define num_shift 2

#define bool_mask 0b1111111
#define bool_tag 0b0011111
#define bool_shift 7

// Task 3.1: Define the ref_tag and ref_mask.
#define ref_mask 0b111
#define ref_tag 0b001

void print_value(uint64_t value)
{
  if ((value & num_mask) == num_tag)
  {
    int64_t ivalue = (int64_t)value;
    printf("%" PRIi64, ivalue >> num_shift);
  }
  else if ((value & bool_mask) == bool_tag)
  {
    if (value >> bool_shift)
    {
      printf("true");
    }
    else
    {
      printf("false");
    }
  } // Task 3.1: Implement printing of references.
  else if ((value & ref_mask) == ref_tag)
  {
    uint64_t v = *(uint64_t *)(value - ref_tag);
    printf("(ref ");
    print_value(v);
    printf(")");
  }
  else
  {
    printf("BAD VALUE: %" PRIu64, value);
  }
}

void error()
{
  printf("ERROR");
  exit(1);
}

int main(int argc, char **argv)
{
  void *heap = (void *)malloc(4096);
  print_value(lisp_entry(heap));
  return 0;
}
