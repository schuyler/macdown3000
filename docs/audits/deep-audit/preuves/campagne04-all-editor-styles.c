#include <stdio.h>
#include <stdlib.h>
#include "pmh_styleparser.h"
static void error(char *message,int line,void *context){(*(int *)context)++;fprintf(stderr,"%d: %s\n",line,message);}
int main(int argc,char **argv){int failures=0;for(int i=1;i<argc;i++){FILE *f=fopen(argv[i],"rb");if(!f||fseek(f,0,SEEK_END))return 2;long size=ftell(f);if(size<0||size>65536||fseek(f,0,SEEK_SET))return 2;char *text=calloc((size_t)size+1,1);if(!text||fread(text,1,size,f)!=(size_t)size)return 2;fclose(f);int errors=0;pmh_style_collection *styles=pmh_parse_styles(text,error,&errors);if(!styles)errors++;if(styles)pmh_free_style_collection(styles);free(text);failures+=errors;printf("%s %s\n",errors?"FAIL":"PASS",argv[i]);}return failures?1:0;}
