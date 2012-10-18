/*
COPYRIGHT & LICENSE

Copyright 2006 Matt Stofko

This program is free software; you can redistribute it and/or
modify it under the terms of either:

* the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

* the Artistic License version 2.0.

*/

extern void ASKInitialize();
extern int NSApplicationMain(int argc, const char *argv[]);

int main(int argc, const char *argv[])
{
    ASKInitialize();

    return NSApplicationMain(argc, argv);
}
