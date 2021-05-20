'use strict';

var aws = require("aws-sdk");
var client = new aws.SecretsManager({
    region: 'us-east-1'
});
var secret, decodedBinarySecret;

exports.handler = (event, context, callback) => {
    client.getSecretValue({
        SecretId: 'internal-docs-password'
    }, function(err, data) {
        if (err) {
            if (err.code === 'DecryptionFailureException')
                throw err;
            else if (err.code === 'InternalServiceErrorException')
                throw err;
            else if (err.code === 'InvalidParameterException')
                throw err;
            else if (err.code === 'InvalidRequestException')
                throw err;
            else if (err.code === 'ResourceNotFoundException')
                throw err;
        } else {
            // Decrypts secret using the associated KMS CMK.
            // Depending on whether the secret is a string or binary, one of these fields will be populated.
            if ('SecretString' in data) {
                secret = data.SecretString;
            } else {
                let buff = new Buffer(data.SecretBinary, 'base64');
                decodedBinarySecret = buff.toString('ascii');
            }
        }
    
    // Get request and request headers
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // Configure authentication
    const authUser = 'Magnolia';
    const authPass = secret;

    // Construct the Basic Auth string
    const authString = 'Basic ' + new Buffer(authUser + ':' + authPass).toString('base64');

    // Require Basic authentication
    if (typeof headers.authorization == 'undefined' || headers.authorization[0].value != authString) {
        const body = 'Unauthorized';
        const response = {
            status: '401',
            statusDescription: 'Unauthorized',
            body: body,
            headers: {
                'www-authenticate': [{key: 'WWW-Authenticate', value:'Basic'}]
            },
        };
        callback(null, response);
    }

    // Continue request processing if authentication passed
    callback(null, request);
    });
};