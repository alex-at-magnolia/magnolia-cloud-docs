/**
 * Adds the ability to convert fully qualified class names into links to the
 * Javadoc page on the class.
 *
 * This is done thanks to a REST call to Nexus, in order to fetch the latest
 * released version of the class, to then assemble its Javadoc URL. It would be
 * possible to parametrize which version to look up, and even ranges.
 *
 * This script purposefully depends on `sync-request`. I haven't found a lot of
 * documentation on writing AsciiDoc macros with Javascript, but what I've
 * found empirically is that AsciiDoc renders the content and does not come
 * back to it. Hence, in order for the content to be there when the macro is
 * called, the request absolutely has to be blocking.
 *
 * Nexus requires that we specify in which repository the target class should
 * be. By default, `magnolia.public.releases` will be used, but
 * `magnolia.enterprise.releases` will be used with the `isEnterprise=true`
 * argument.
 *
 * Examples:
 *
 *   javadoc:info.magnolia.usagemetrics.ConfigScannerCommand[]
 *   javadoc:info.magnolia.license.LicenseUtil[isEnterprise=true]
 *
 * Inspired from: https://pagure.io/fedora-docs/docs-fp-o/pull-request/93.patch
 */
const request = require('sync-request')

function initInlineManMacro ({ file }) {
  return function () {
    this.process((parent, target, attrs) => {

      // target looks something like 'info.magnolia.usagemetrics.ConfigScannerCommand'
      const explodedFullyQualifiedClassName = target.split('.')

      // let's extract 'ConfigScannerCommand', which will be the link anchor
      const shortenedClassName = explodedFullyQualifiedClassName[explodedFullyQualifiedClassName.length - 1]

      const attributes = Opal.hash2(['window'], { window: '_blank' })

      if (!process.env.NEXUS_USERNAME || !process.env.NEXUS_PASSWORD) {
        console.log('Environment variables NEXUS_USERNAME and/or NEXUS_PASSWORD not present, not looking up Javadoc links.')
        return this.createInline(parent, 'anchor', shortenedClassName, { type: 'link', target: '#', attributes })
      }

      // blocking REST call to nexus
      var res = request('GET', 'https://nexus.magnolia-cms.com/service/local/lucene/search', {
        qs: {
          cn: target
        },
        headers: {
          Accept: 'application/json', // force nexus to produce JSON rather than XML
          Authorization: 'Basic ' + Buffer.from(process.env.NEXUS_USERNAME + ':' + process.env.NEXUS_PASSWORD).toString('base64')
        }
      })

      console.log('Nexus search done for: ' + target)
      // all results will return the same groupId, artifactId and latestRelease
      // so we can just pick the first one
      const nexusResult = JSON.parse(res.getBody('utf8')).data[0]

      const groupId = nexusResult.groupId
      const artifactId = nexusResult.artifactId
      const version = nexusResult.latestRelease

      // let's assemble an URL like the following with the information we have:
      // https://nexus.magnolia-cms.com/service/local/repositories/magnolia.public.releases/archive/info/magnolia/rest/magnolia-rest-integration/1.2.2/magnolia-rest-integration-1.2.2-javadoc.jar/!/info/magnolia/rest/RestDispatcherServlet.html
      let url = 'https://nexus.magnolia-cms.com'
      url += '/service/local/repositories/'
      url += attrs.isEnterprise ? 'magnolia.enterprise.releases' : 'magnolia.public.releases'
      url += '/archive/'
      url += groupId.split('.').join('/') // convert info.magnolia.usagemetrics into info/magnolia/usagemetrics
      url += '/'
      url += artifactId
      url += '/'
      url += version
      url += '/'
      url += artifactId
      url += '-'
      url += version
      url += '-javadoc.jar/!/'
      url += explodedFullyQualifiedClassName.join('/')
      url += '.html'

      return this.createInline(parent, 'anchor', shortenedClassName, { type: 'link', target: url, attributes })
    })
  }
}

function register (registry, context) {
  registry.inlineMacro('javadoc', initInlineManMacro(context))
}

module.exports.register = register
