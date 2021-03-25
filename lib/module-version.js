/**
 * Defines the `modules-version` property on any page that defines a module's
 * `group-id` and `artifact-id` by using a Nexus REST search.
 *
 * Is implemented as post-processor because a pre-processor hasn't yet parsed
 * the page attributes.
 *
 * For more details on the design, see also `javadoc.js`.
 */
const request = require('sync-request')

function moduleVersionPostprocessor () {
  this.process((doc, out) => {
    if (doc.getAttribute('group-id') && doc.getAttribute('artifact-id')) {
      const groupId = doc.getAttribute('group-id')
      const artifactId = doc.getAttribute('artifact-id')

      if (!process.env.NEXUS_USERNAME || !process.env.NEXUS_PASSWORD) {
        console.log('Environment variables NEXUS_USERNAME and/or NEXUS_PASSWORD not present, not looking up module versions.')
        return out
      }

      // blocking REST call to nexus
      var res = request('GET', 'https://nexus.magnolia-cms.com/service/local/lucene/search', {
        qs: {
          g: groupId,
          a: artifactId
        },
        headers: {
          Accept: 'application/json', // force nexus to produce JSON rather than XML
          Authorization: 'Basic ' + Buffer.from(process.env.NEXUS_USERNAME + ':' + process.env.NEXUS_PASSWORD).toString('base64')
        }
      })

      console.log('Nexus search done for: ' + groupId + ':' + artifactId)
      // all results will return the same groupId, artifactId and latestRelease
      // so we can just pick the first one
      const nexusResult = JSON.parse(res.getBody('utf8')).data[0]

      const version = nexusResult.latestRelease
      doc.setAttribute('modules-version', version)
      console.log('The following version was defined as page attribute: ' + version)
    }
    return out
  })
}

function register (registry) {
  registry.postprocessor(moduleVersionPostprocessor)
}

module.exports.register = register
