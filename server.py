from wsgidav.wsgidav_app import WsgiDAVApp
from wsgidav.fs_dav_provider import FilesystemProvider
from cheroot.wsgi import Server as WSGIServer
from wsgidav.dav_error import DAVError, HTTP_FORBIDDEN

class NoOverwriteFilesystemProvider(FilesystemProvider):
    def create_resource(self, path, collection=False, environ=None, raise_errors=False):
        """
        Override to prevent file creation if it already exists.
        """
        print("create_resource")
        if not collection and self.exists(path, environ):
            # File exists, raise an error to prevent overwrite
            raise DAVError(HTTP_FORBIDDEN, "Overwriting existing files is not allowed.")
        # Proceed with the original behavior for new files or collections (directories)
        return super().create_resource(path, collection=collection, environ=environ, raise_errors=raise_errors)

    def begin_write(self, path, environ=None):
        """
        Override to prevent file overwrite on write.
        """
        print("begin_write")
        if self.exists(path, environ):
            # File exists, raise an error to prevent overwrite
            raise DAVError(HTTP_FORBIDDEN, "Overwriting existing files is not allowed.")
        # Proceed with original behavior for new files
        return super().begin_write(path, environ=environ)

def create_webdav_server(host="0.0.0.0", port=8080, root_folder="/Users/aleksandrvin/Developer/webdav/data"):
    """
    Create and start a simple WebDAV server.
    
    :param host: The hostname or IP address to bind the server to.
    :param port: The port number for the server.
    :param root_folder: The root directory served by WebDAV.
    """
    config = {
        "host": host,
        "port": port,
        "root_path": root_folder,
        "provider_mapping": {"/": FilesystemProvider(root_folder)},
#        "provider_mapping": {"/": NoOverwriteFilesystemProvider(root_folder)},
        "verbose": 2,
        "simple_dc": {"user_mapping": {
            "*": True,
        }}
    }

    app = WsgiDAVApp(config)
    server = WSGIServer((host, port), app)

    print(f"Starting WebDAV server on {host}:{port}")
    print(f"Serving directory: {root_folder}")
    try:
        server.start()
    except KeyboardInterrupt:
        print("Stopping WebDAV server.")
        server.stop()

if __name__ == "__main__":
    create_webdav_server()
