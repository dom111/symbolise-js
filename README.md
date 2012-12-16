symbolise-js
============

Can you make your scripts smaller?
----------------------------------

Minifying your JavaScript is something most people are familiar with and have to do fairly regularly, whether is reducing your page load time on PC or keeping the files within the mobile cache limits.

Having recently seen UglifyJS and having used some of the more obvious tricks (!0 === true, !1 === false, etc) myself, I wondered if there was a way you could shrink down what’s transferred even more…

As a proof of concept I’ve knocked up a (hopefully fairly) simple perl script that will wrap your code in a closure and replace a lot of the internal indexes that are used with global symbols, which when compressed with YUI/Uglify should reduce filesize overall.

I’ve already been using this method in bookmarklets, and I’m sure many others have too, but I couldn’t find an existing tool to do this (and I thought it would be interesting trying to break JavaScript files down for parsing…).

In case you don’t know, the dot notation in JS is just a shorthand for using square brackets:

    var obj = { 'test': true, 'value': 'Hello World!' };
    obj.test; // true
    obj['test']; // true

which means you can also do:

    var k = 'test';
    obj[k]; // true

In simple bookmarklets I often have a few calls to getElementsByTagName or querySelectorAll which I reference in the main closure as strings in variables like getElementsByTagName__ or querySelectorAll__, so I wanted to see if it was possible to automate this process, and if so how hard it would be.

Well, it was pretty frustrating and I’m sure it hasn’t worked out as anywhere near the simplest solution (I am almost certain the regular expressions could be simplified!) but I thought I’d share in case anyone else thinks the same and could perhaps improve upon this or point me to an existing solution.

Here are some size comparisons using jQuery 1.8.3 as an example.

Standard Library:
-----------------

* raw: 331,286 bytes
* min (jquery.min): 93,636 bytes
* yui: 105,103 bytes
* uglify: 92,604 bytes

Parsed:
-------

* raw: 369,687 bytes
* yui: 95,093 bytes
* uglify: 82,682 bytes

Now there are some drawbacks with my implementation here, it won’t remove or add to an existing closure, so you might have redundant code at the tope of your file, but as this is just a proof of concept I haven’t really parsed the JS so I didn’t want to potentially trash anything… Also if you rely on being in the global scope (Prototype for example) this will likely break your script. Other than that I haven’t encountered anything that’s been broken in this jQuery example by the process, but that certainly doesn’t mean nothing’s broken! I’ve also assumed DOM-centric script, using this as a short reference to the window as the default in minify.pl, but in Symbolise.pm it’s disabled by default.

Are there any other tricks that could get even more bytes squeezed?

Does gzip totally negate this work? (Probably does, but this was interesting nonetheless!)

If you’d like to play with this yourself, you can access the perl script here or there’s a github repository.

To use it, put it in a folder and run:

    perl minify.pl filename.js > filename-parsed.js
