===============================================================================

RecordingStudioApi has been installed successfully!

The engine has been mounted at /recording_studio_api in your application.

If you use Tailwind CSS:
1. Run 'bin/rails tailwindcss:build' to rebuild your CSS with RecordingStudioApi styles

To use the engine:
1. Start your Rails server
2. Wire your API routes and host-app review surface as needed; the gem does not ship a browser root page
3. Register custom capability handlers so they authorize through the passed RecordingStudioApi access grant before doing work

For separate public and site-administration APIs, configure each named API and then run:

	bin/rails generate recording_studio_api:admin_screens \
		--user-roots Workspace --user-apis public \
		--admin-roots AdminRoot --admin-apis public operations

Enable Recording Studio's accessible and api_access_point capabilities on each root that can receive
credentials. Access points are still limited to recordables registered on the selected API.

===============================================================================
