#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# proxy.py — helper for Python-based external (xml-rpc) ikiwiki plugins
#
# Copyright © martin f. krafft <madduck@madduck.net>
# Released under the terms of the GNU GPL version 2
#
__name__ = 'proxy.py'
__description__ = 'helper for Python-based external (xml-rpc) ikiwiki plugins'
__version__ = '0.1'
__author__ = 'martin f. krafft <madduck@madduck.net>'
__copyright__ = 'Copyright © ' + __author__
__licence__ = 'GPLv2'

import sys
import time
import xmlrpclib
import xml.parsers.expat
from SimpleXMLRPCServer import SimpleXMLRPCDispatcher

class _IkiWikiExtPluginXMLRPCDispatcher(SimpleXMLRPCDispatcher):

    def __init__(self, allow_none=False, encoding=None):
        try:
            SimpleXMLRPCDispatcher.__init__(self, allow_none, encoding)
        except TypeError:
            # see http://bugs.debian.org/470645
            # python2.4 and before only took one argument
            SimpleXMLRPCDispatcher.__init__(self)

    def dispatch(self, method, params):
        return self._dispatch(method, params)

class XMLStreamParser(object):

    def __init__(self):
        self._parser = xml.parsers.expat.ParserCreate()
        self._parser.StartElementHandler = self._push_tag
        self._parser.EndElementHandler = self._pop_tag
        self._parser.XmlDeclHandler = self._check_pipelining
        self._reset()

    def _reset(self):
        self._stack = list()
        self._acc = r''
        self._first_tag_received = False

    def _push_tag(self, tag, attrs):
        self._stack.append(tag)
        self._first_tag_received = True

    def _pop_tag(self, tag):
        top = self._stack.pop()
        if top != tag:
            raise ParseError, 'expected %s closing tag, got %s' % (top, tag)

    def _request_complete(self):
        return self._first_tag_received and len(self._stack) == 0

    def _check_pipelining(self, *args):
        if self._first_tag_received:
            raise PipeliningDetected, 'need a new line between XML documents'

    def parse(self, data):
        self._parser.Parse(data, False)
        self._acc += data
        if self._request_complete():
            ret = self._acc
            self._reset()
            return ret

    class ParseError(Exception):
        pass

    class PipeliningDetected(Exception):
        pass

class _IkiWikiExtPluginXMLRPCHandler(object):

    def __init__(self, debug_fn):
        self._dispatcher = _IkiWikiExtPluginXMLRPCDispatcher()
        self.register_function = self._dispatcher.register_function
        self._debug_fn = debug_fn

    def register_function(self, function, name=None):
        # will be overwritten by __init__
        pass

    @staticmethod
    def _write(out_fd, data):
        out_fd.write(str(data))
        out_fd.flush()

    @staticmethod
    def _read(in_fd):
        ret = None
        parser = XMLStreamParser()
        while True:
            line = in_fd.readline()
            if len(line) == 0:
                # ikiwiki exited, EOF received
                return None

            ret = parser.parse(line)
            # unless this returns non-None, we need to loop again
            if ret is not None:
                return ret

    def send_rpc(self, cmd, in_fd, out_fd, *args, **kwargs):
        xml = xmlrpclib.dumps(sum(kwargs.iteritems(), args), cmd)
        self._debug_fn("calling ikiwiki procedure `%s': [%s]" % (cmd, xml))
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, xml)

        self._debug_fn('reading response from ikiwiki...')

        xml = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        self._debug_fn('read response to procedure %s from ikiwiki: [%s]' % (cmd, xml))
        if xml is None:
            # ikiwiki is going down
            self._debug_fn('ikiwiki is going down, and so are we...')
            raise _IkiWikiExtPluginXMLRPCHandler._GoingDown

        data = xmlrpclib.loads(xml)[0][0]
        self._debug_fn('parsed data from response to procedure %s: [%s]' % (cmd, data))
        return data

    def handle_rpc(self, in_fd, out_fd):
        self._debug_fn('waiting for procedure calls from ikiwiki...')
        xml = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        if xml is None:
            # ikiwiki is going down
            self._debug_fn('ikiwiki is going down, and so are we...')
            raise _IkiWikiExtPluginXMLRPCHandler._GoingDown

        self._debug_fn('received procedure call from ikiwiki: [%s]' % xml)
        params, method = xmlrpclib.loads(xml)
        ret = self._dispatcher.dispatch(method, params)
        xml = xmlrpclib.dumps((ret,), methodresponse=True)
        self._debug_fn('sending procedure response to ikiwiki: [%s]' % xml)
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, xml)
        return ret

    class _GoingDown:
        pass

class IkiWikiProcedureProxy(object):

    # how to communicate None to ikiwiki
    _IKIWIKI_NIL_SENTINEL = {'null':''}

    # sleep during each iteration
    _LOOP_DELAY = 0.1

    def __init__(self, id, in_fd=sys.stdin, out_fd=sys.stdout, debug_fn=None):
        self._id = id
        self._in_fd = in_fd
        self._out_fd = out_fd
        self._hooks = list()
        self._functions = list()
        self._imported = False
        if debug_fn is not None:
            self._debug_fn = debug_fn
        else:
            self._debug_fn = lambda s: None
        self._xmlrpc_handler = _IkiWikiExtPluginXMLRPCHandler(self._debug_fn)
        self._xmlrpc_handler.register_function(self._importme, name='import')

    def rpc(self, cmd, *args, **kwargs):
        def subst_none(seq):
            for i in seq:
                if i is None:
                    yield IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
                else:
                    yield i

        args = list(subst_none(args))
        kwargs = dict(zip(kwargs.keys(), list(subst_none(kwargs.itervalues()))))
        ret = self._xmlrpc_handler.send_rpc(cmd, self._in_fd, self._out_fd,
                                            *args, **kwargs)
        if ret == IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL:
            ret = None
        return ret

    def hook(self, type, function, name=None, id=None, last=False):
        if self._imported:
            raise IkiWikiProcedureProxy.AlreadyImported

        if name is None:
            name = function.__name__

        if id is None:
            id = self._id

        def hook_proxy(*args):
#            curpage = args[0]
#            kwargs = dict([args[i:i+2] for i in xrange(1, len(args), 2)])
            ret = function(self, *args)
            self._debug_fn("%s hook `%s' returned: [%s]" % (type, name, ret))
            if ret == IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL:
                raise IkiWikiProcedureProxy.InvalidReturnValue, \
                        'hook functions are not allowed to return %s' \
                        % IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
            if ret is None:
                ret = IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
            return ret

        self._hooks.append((id, type, name, last))
        self._xmlrpc_handler.register_function(hook_proxy, name=name)

    def inject(self, rname, function, name=None, memoize=True):
        if self._imported:
            raise IkiWikiProcedureProxy.AlreadyImported

        if name is None:
            name = function.__name__

        self._functions.append((rname, name, memoize))
        self._xmlrpc_handler.register_function(function, name=name)

    def getargv(self):
        return self.rpc('getargv')

    def setargv(self, argv):
        return self.rpc('setargv', argv)

    def getvar(self, hash, key):
        return self.rpc('getvar', hash, key)

    def setvar(self, hash, key, value):
        return self.rpc('setvar', hash, key, value)

    def getstate(self, page, id, key):
        return self.rpc('getstate', page, id, key)

    def setstate(self, page, id, key, value):
        return self.rpc('setstate', page, id, key, value)

    def pagespec_match(self, spec):
        return self.rpc('pagespec_match', spec)

    def error(self, msg):
        try:
            self.rpc('error', msg)
        except IOError, e:
            if e.errno != 32:
                raise
        import posix
        sys.exit(posix.EX_SOFTWARE)

    def run(self):
        try:
            while True:
                ret = self._xmlrpc_handler.handle_rpc(self._in_fd, self._out_fd)
                time.sleep(IkiWikiProcedureProxy._LOOP_DELAY)
        except _IkiWikiExtPluginXMLRPCHandler._GoingDown:
            return

        except Exception, e:
            import traceback
            self.error('uncaught exception: %s\n%s' \
                       % (e, traceback.format_exc(sys.exc_info()[2])))
            return

    def _importme(self):
        self._debug_fn('importing...')
        for id, type, function, last in self._hooks:
            self._debug_fn('hooking %s/%s into %s chain...' % (id, function, type))
            self.rpc('hook', id=id, type=type, call=function, last=last)
        for rname, function, memoize in self._functions:
            self._debug_fn('injecting %s as %s...' % (function, rname))
            self.rpc('inject', name=rname, call=function, memoize=memoize)
        self._imported = True
        return IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL

    class InvalidReturnValue(Exception):
        pass

    class AlreadyImported(Exception):
        pass
