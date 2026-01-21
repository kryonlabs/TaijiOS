#include "os.h"
#include "../include/mp.h"
#include "dat.h"

Mfield*
mpfield(mpint *N)
{
	Mfield *f;

	if(N == nil || N->flags & (MPfield|MPstatic))
		return (Mfield*)N;
	if((f = cnfield(N)) != nil)
		goto Exchange;
	if((f = gmfield(N)) != nil)
		goto Exchange;
	return (Mfield*)N;
Exchange:
	setmalloctag(f, getcallerpc(&N));
	// Copy the mpint data to the Mfield
	f->sign = N->sign;
	f->size = N->size;
	f->top = N->top;
	f->p = N->p;
	f->flags = N->flags;
	free(N);
	return f;
}
