
/* FPdbleword for mptod.c */
#ifndef FPdbleword_defined
#define FPdbleword_defined
typedef union FPdbleword FPdbleword;
union FPdbleword {
	double	x;
	struct {	
		uint lo;
		uint hi;
	};
};
#endif
