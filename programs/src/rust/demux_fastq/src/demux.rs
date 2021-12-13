use simple_error::{simple_error, SimpleError};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

use seq_io::fastq::{Record, RefRecord};

use crate::fastq::{with_thread_reader_from_file, IoPool};

pub struct Demultiplexer {
    pub assignments: Vec<BarcodeAssignment>,
    pub threads: usize,
    pub mismatches: u8,
}
impl Demultiplexer {
    pub fn run(&self, input: &Option<PathBuf>) {
        let mut iopool = IoPool::new(self.threads);
        // Open a writer for each file and create our barcode->writer mapping
        let (demux_map, mut writers) =
            generate_demux_map(&self.assignments, &mut iopool, self.mismatches);

        // Open the input for reading
        let result = with_thread_reader_from_file(input.as_ref().unwrap(), |rdr| {
            let mut reader = seq_io::fastq::Reader::new(rdr);

            // Read each record from input
            while let Some(r) = reader.next() {
                let record = r.expect("Invalid record");
                // Find the barcode
                let bc = get_record_bc(&record);
                // If the barcode matches our records, write it to the correct writer
                if let Some(index) = demux_map.get(bc) {
                    let w = &mut writers[*index];
                    record
                        .write_unchanged(w)
                        .expect("could not write record to output");
                }
                // else do nothing
            }
            for mut w in writers {
                w.close().expect("Couldn't write");
            }
            Ok::<_, std::io::Error>(())
        });
        result.unwrap();
    }
}

fn get_record_bc<'a>(record: &'a RefRecord) -> &'a [u8] {
    // The barcode is everything in the name/description line after the last colon
    let sep = b':';
    let id = record.head();
    let slicestart = id.len()
        - id.iter()
            .rev()
            .position(|x| *x == sep)
            .expect("no bc in record");
    &id[slicestart..]
}

#[derive(Debug, Clone)]
pub struct BarcodeAssignment {
    barcode: String,
    filepath: PathBuf,
}
impl std::str::FromStr for BarcodeAssignment {
    type Err = SimpleError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.split_once('=') {
            Some((barcode, path_string)) if !barcode.is_empty() && !path_string.is_empty() => {
                Ok(BarcodeAssignment {
                    barcode: barcode.to_string(),
                    filepath: PathBuf::from_str(path_string).unwrap(),
                })
            }

            _ => Err(simple_error!(
                "'{}' does not match barcode format: 'barcode=file'",
                s
            )),
        }
    }
}
/// This returns a map of barcodes to Open writers
fn generate_demux_map<'a>(
    barcodes: &Vec<BarcodeAssignment>,
    pool: &'a mut IoPool,
    mismatches: u8,
) -> (
    HashMap<Vec<u8>, usize>,
    Vec<autocompress::iothread::BlockWriter<'a, impl std::io::Write>>,
) {
    let mut path_map: HashMap<PathBuf, usize> = HashMap::new();

    let mut paths = Vec::new();
    {
        let mut i = 0;
        for ba in barcodes.iter() {
            let path = ba.filepath.clone();
            if !path_map.contains_key(&path) {
                paths.push(path.clone());
                path_map.insert(path, i);
                i += 1;
            }
        }
    }
    let v = pool.get_writers(paths);

    let mut barcode_map = HashMap::new();
    for ba in barcodes.iter() {
        let w = path_map[&ba.filepath];
        for barcode in generate_mismatches(ba.barcode.clone(), mismatches) {
            let b = barcode.as_bytes().to_vec();
            barcode_map.insert(b, w);
        }
    }
    (barcode_map, v)
}

const VALID_BASES: &[char] = &['A', 'C', 'G', 'T', 'N'];
fn generate_mismatches(input: String, mismatches: u8) -> Vec<String> {
    if mismatches == 0 {
        return Vec::from([input]);
    }

    // Create with just the original version.
    let mut v = Vec::new();
    v.push(input.clone());
    let chars: Vec<char> = input.chars().collect();
    // Create all mutations
    for (idx, base) in chars.iter().enumerate() {
        // Only modify bases that are ACTGN (not + or other separators)
        if VALID_BASES.contains(&base) {
            for new_base in VALID_BASES.iter() {
                // Don't bother emitting
                if base != new_base {
                    let mut new_bc: Vec<char> = chars.clone();
                    new_bc[idx] = *new_base;
                    v.push(new_bc.iter().collect());
                }
            }
        }
    }
    // If necessary, feed these to another level of mismatch generation
    // HashSet is for de-duplication
    let bc_set: HashSet<String> = v
        .iter()
        .map(|bc| generate_mismatches(bc.clone(), mismatches - 1))
        .fold(Vec::new(), |mut acc, mut v| {
            acc.append(&mut v);
            acc
        })
        .into_iter()
        .collect();
    bc_set.into_iter().collect()
}
