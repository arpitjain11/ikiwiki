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

LOOP_DELAY = 0.1

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

class _XMLStreamParser(object):

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

    def __init__(self, debug_fn, allow_none=False, encoding=None):
        self._dispatcher = _IkiWikiExtPluginXMLRPCDispatcher(allow_none, encoding)
        self.register_function = self._dispatcher.register_function
        self._debug_fn = debug_fn

    def register_function(self, function, name=None):
        # will be overwritten by __init__
        pass

    @staticmethod
    def _write(out_fd, data):
        out_fd.write(data)
        out_fd.flush()

    @staticmethod
    def _read(in_fd):
        ret = None
        parser = _XMLStreamParser()
        while True:
            line = in_fd.readline()
            if len(line) == 0:
                # ikiwiki exited, EOF received
                return None

            ret = parser.parse(line)
            # unless this returns non-None, we need to loop again
            if ret is not None:
                return ret

    def send_rpc(self, cmd, in_fd, out_fd, **kwargs):
        xml = xmlrpclib.dumps(sum(kwargs.iteritems(), ()), cmd)
        self._debug_fn('sending xml to ikiwiki to call procedure %s: [%s]' % (cmd, xml))
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, xml)

        self._debug_fn('reading response from ikiwiki...')

        xml = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        self._debug_fn('read response to procedure %s from ikiwiki: [%s]' % (cmd, xml))
        if xml is None:
            # ikiwiki is going down
            return None

        data = xmlrpclib.loads(xml)[0]
        self._debug_fn('parsed data from response to procedure %s: [%s]' % (cmd, data))
        return data

    def handle_rpc(self, in_fd, out_fd):
        self._debug_fn('waiting for procedure calls from ikiwiki...')
        ret = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        if ret is None:
            # ikiwiki is going down
            self._debug_fn('ikiwiki is going down, and so are we...')
            return

        self._debug_fn('received procedure call from ikiwiki: [%s]' % ret)
        ret = self._dispatcher._marshaled_dispatch(ret)
        self._debug_fn('sending procedure response to ikiwiki: [%s]' % ret)
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, ret)
        return ret

class IkiWikiProcedureProxy(object):

    def __init__(self, id, in_fd=sys.stdin, out_fd=sys.stdout, debug_fn=None):
        self._id = id
        self._in_fd = in_fd
        self._out_fd = out_fd
        self._hooks = list()
        if debug_fn is not None:
            self._debug_fn = debug_fn
        else:
            self._debug_fn = lambda s: None
        self._xmlrpc_handler = _IkiWikiExtPluginXMLRPCHandler(self._debug_fn)
        self._xmlrpc_handler.register_function(self._importme, name='import')

    def register_hook(self, type, function):
        self._hooks.append((type, function.__name__))
        self._xmlrpc_handler.register_function(function)

    def _importme(self):
        self._debug_fn('importing...')
        for type, function in self._hooks:
            self._debug_fn('hooking %s into %s chain...' % (function, type))
            self._xmlrpc_handler.send_rpc('hook', self._in_fd, self._out_fd,
                                          id=self._id, type=type, call=function)
        return 0

    def run(self):
        try:
            while True:
                ret = self._xmlrpc_handler.handle_rpc(self._in_fd, self._out_fd)
                if ret is None:
                    return
                time.sleep(LOOP_DELAY)
        except Exception, e:
            self._debug_fn('uncaught exception: %s' % e)
            sys.exit(posix.EX_SOFTWARE)