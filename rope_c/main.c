#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LEAF_LEN 2

// #define UN_INT
#ifdef UN_INT
void un_int_value() {
  int val;
  printf("%d", val);
}
#endif // UN_INT

typedef struct Rope {
  struct Rope *left, *right, *parent;
  char *str;
  int lCount;
} Rope;

void createRope(Rope *ro, Rope *par, char a[], int l, int r) {
  Rope tmp = {0};
  tmp.parent = par;

  if ((r - l) > LEAF_LEN) {
    tmp.lCount = (r - l) / 2;
    ro = &tmp;
    int m = (l + r) / 2;
    createRope(ro->left, ro, a, l, m);
    createRope(ro->right, ro, a, l, m);
  } else {
    ro = &tmp;
    tmp.lCount = (r - l) / 2;
    memcpy(tmp.str, &a, strlen(a));
  }
}

int main(void) {
  Rope *root1 = NULL;
  char a[] = "Hi This is geeksforgeeks. ";
  int n1 = sizeof(a) / sizeof(a[0]);
  createRope(root1, NULL, a, 0, n1 - 1);
  return EXIT_SUCCESS;
}
