const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const {get, keyBy, pick} = require('lodash');

const outputFilename = get(process.argv, '[2]') || 'components-meta.json';
const componentsDirectory = get(process.argv, '[3]') || '../../../components';

function write(filename, value) {
    const out = fs.openSync(filename, 'w');
    fs.writeFileSync(out, JSON.stringify(value, undefined, 2));
    fs.closeSync(out);
}

function extract(components) {
    return keyBy(
        components.map(([name, {meta, requires = [], provides = []}]) => ({
            name,
            ...pick(meta, [
                'brief', 'version', 'maturity', 'license', 'title', 'description', 'category', 'disabled'
            ]),
            requires,
            provides
        })),
        'name');
}

function read(components) {
    return components.map(([name, filename]) => [name, yaml.safeLoad(fs.readFileSync(filename))]);
}

function scan(directory) {
    return fs.readdirSync(directory)
        .map((name) => [name, path.join(directory, name, 'hub-component.yaml')])
        .filter(([, filename]) => fs.existsSync(filename));
}

write(outputFilename, extract(read(scan(componentsDirectory))));
